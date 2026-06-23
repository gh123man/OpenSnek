import Foundation
import IOKit.hid
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

extension BridgeClient {
    func apply(device: MouseDevice, patch: DevicePatch, options: ApplyOptions = ApplyOptions()) async throws -> MouseState {
        if device.transport == .bluetooth {
            return try await applyBluetooth(device: device, patch: patch)
        }
        return try await applyUSB(device: device, patch: patch, options: options)
    }

    private func applyBluetooth(device: MouseDevice, patch: DevicePatch) async throws -> MouseState {
        let changedDpi = patch.affectsDpiStages
        let changedLighting = patch.ledBrightness != nil || patch.ledRGB != nil || patch.lightingEffect != nil
        let changedPower = patch.sleepTimeout != nil

        if patch.affectsDpiStages {
            let current: BLEVendorProtocol.DpiStageSnapshot?
            if let cached = btDpiSnapshotByDeviceID[device.id] {
                current = cached
            } else {
                current = try await btGetDpiStageSnapshot(device: device)
            }
            let resolved = try Self.resolveBluetoothDpiStageWrite(
                device: device,
                patch: patch,
                current: current
            )
            guard try await btSetDpiStages(device: device, active: resolved.active, values: resolved.stages, pairs: resolved.pairs) else {
                throw BridgeError.commandFailed("Failed to set Bluetooth DPI stages")
            }
        }

        if let brightness = patch.ledBrightness,
           device.supportsLightingBrightnessControls {
            guard try await btSetLightingValue(device: device, value: brightness) else {
                throw BridgeError.commandFailed("Failed to set Bluetooth lighting value")
            }
        }

        if let rgb = patch.ledRGB {
            guard try await btSetLightingRGB(
                device: device,
                r: rgb.r,
                g: rgb.g,
                b: rgb.b,
                ledIDs: patch.usbLightingZoneLEDIDs
            ) else {
                throw BridgeError.commandFailed("Failed to set Bluetooth RGB")
            }
        }

        if let effect = patch.lightingEffect {
            let ledIDs = effect.kind == .staticColor ? patch.usbLightingZoneLEDIDs : nil
            let applied = try await btApplyLightingEffectFallback(device: device, effect: effect, ledIDs: ledIDs)
            if !applied {
                AppLog.debug(
                    "Bridge",
                    "lighting effect fallback unavailable kind=\(effect.kind.rawValue) transport=\(device.transport.rawValue)"
                )
            }
        }

        if let binding = patch.buttonBinding {
            let slot = UInt8(max(0, min(255, binding.slot)))
            let kind = binding.kind
            let hidKey = UInt8(max(0, min(255, binding.hidKey ?? 4)))
            let hidModifiers = UInt8(max(0, min(255, binding.hidModifiers ?? 0)))
            let turboEnabled = kind.supportsTurbo && binding.turboEnabled
            let turboRate = UInt16(
                ButtonBindingSupport.clampTurboRate(binding.turboRate ?? ButtonBindingSupport.defaultTurboRate)
            )
            let clutchDPI = kind == .dpiClutch
                ? DeviceProfiles.clampDPI(
                    binding.clutchDPI ?? ButtonBindingSupport.defaultBasiliskDPIClutchDPI,
                    device: device
                )
                : nil
            guard try await btSetButtonBinding(
                BluetoothButtonBindingWrite(
                    device: device,
                    slot: slot,
                    kind: kind,
                    hidKey: hidKey,
                    hidModifiers: hidModifiers,
                    turboEnabled: turboEnabled,
                    turboRate: turboRate,
                    clutchDPI: clutchDPI
                )
            ) else {
                throw BridgeError.commandFailed("Failed to set Bluetooth button binding")
            }
        }

        if let timeout = patch.sleepTimeout {
            let clamped = max(60, min(900, timeout))
            guard try await btSetScalar(
                device: device,
                key: .powerTimeoutSet,
                value: clamped,
                size: 2,
                payloadLength: 0x02
            ) else {
                throw BridgeError.commandFailed("Failed to set Bluetooth sleep timeout")
            }
        }

        return try await buildBluetoothDeltaState(
            device: device,
            includeDpi: changedDpi,
            includeLighting: changedLighting,
            includePower: changedPower
        )
    }

    private func applyUSB(device: MouseDevice, patch: DevicePatch, options: ApplyOptions) async throws -> MouseState {
        try await deferUSBReconnectReadIfNeeded(deviceID: device.id, operation: "apply")
        let orderedSessions = sessionsFor(device: device)
        guard !orderedSessions.isEmpty else {
            if managerAccessDenied {
                throw BridgeError.commandFailed(
                    "USB HID access denied by macOS. Enable Input Monitoring for OpenSnek " +
                    "(or Terminal/Xcode when running via swift run/Xcode), then relaunch."
                )
            }
            throw BridgeError.commandFailed("Device not available")
        }
        func runUSBWrite(_ operation: (USBHIDControlSession) throws -> Bool) throws -> Bool {
            let session = orderedSessions[0]
            let succeeded = try session.withExclusiveDeviceAccess { try operation(session) }
            if succeeded {
                deviceSessions[device.id] = session
            }
            return succeeded
        }

        func readUSBCurrentDpiStages() throws -> USBDpiStageSnapshot? {
            let session = orderedSessions[0]
            let current = try session.withExclusiveDeviceAccess {
                try getDPIStageSnapshot(session, device)
            }
            if current != nil {
                deviceSessions[device.id] = session
            }
            return current
        }

        func readUSBCurrentDpi() throws -> (Int, Int)? {
            let session = orderedSessions[0]
            let current = try session.withExclusiveDeviceAccess {
                try getDPI(session, device)
            }
            if current != nil {
                deviceSessions[device.id] = session
            }
            return current
        }

        try applyUSBScalarSettings(device: device, patch: patch, runUSBWrite: runUSBWrite)

        if let projected = try await applyUSBDpiPatchIfNeeded(
            device: device,
            patch: patch,
            runUSBWrite: runUSBWrite,
            readUSBCurrentDpiStages: readUSBCurrentDpiStages,
            readUSBCurrentDpi: readUSBCurrentDpi
        ) {
            return projected
        }

        if let brightness = patch.ledBrightness,
           device.supportsLightingBrightnessControls {
            guard try runUSBWrite({ try setScrollLEDBrightness($0, device, value: brightness) }) else {
                throw BridgeError.commandFailed("Failed to set LED brightness")
            }
        }

        if let rgb = patch.ledRGB {
            let effect = LightingEffectPatch(
                kind: .staticColor,
                primary: RGBPatch(r: rgb.r, g: rgb.g, b: rgb.b)
            )
            let ledIDs = effect.kind == .staticColor ? patch.usbLightingZoneLEDIDs : nil
            guard try runUSBWrite({ try setScrollLEDEffect($0, device, effect: effect, ledIDs: ledIDs) }) else {
                throw BridgeError.commandFailed("Failed to set LED color")
            }
        }

        if let effect = patch.lightingEffect {
            let ledIDs = effect.kind == .staticColor ? patch.usbLightingZoneLEDIDs : nil
            guard try runUSBWrite({ try setScrollLEDEffect($0, device, effect: effect, ledIDs: ledIDs) }) else {
                throw BridgeError.commandFailed("Failed to set lighting effect")
            }
        }

        if let usbButtonProfileAction = patch.usbButtonProfileAction {
            switch usbButtonProfileAction.kind {
            case .projectToDirectLayer:
                guard try runUSBWrite({
                    try projectUSBButtonProfileToDirectLayer(
                        $0,
                        device,
                        profile: UInt8(usbButtonProfileAction.targetProfile)
                    )
                }) else {
                    throw BridgeError.commandFailed("Failed to project USB button profile to direct layer")
                }
            case .duplicateToPersistentSlot:
                guard let sourceProfile = usbButtonProfileAction.sourceProfile else {
                    throw BridgeError.commandFailed("Missing source USB button profile")
                }
                guard try runUSBWrite({
                    try duplicateUSBButtonProfile(
                        $0,
                        device,
                        sourceProfile: UInt8(sourceProfile),
                        targetProfile: UInt8(usbButtonProfileAction.targetProfile)
                    )
                }) else {
                    throw BridgeError.commandFailed("Failed to duplicate USB button profile")
                }
            case .resetPersistentSlot:
                guard try runUSBWrite({
                    try resetUSBButtonProfile(
                        $0,
                        device,
                        profile: UInt8(usbButtonProfileAction.targetProfile)
                    )
                }) else {
                    throw BridgeError.commandFailed("Failed to reset USB button profile")
                }
            }
        }

        if let binding = patch.buttonBinding {
            let slot = binding.slot
            let kind = binding.kind.rawValue
            let hidKey = binding.hidKey ?? 4
            let hidModifiers = binding.hidModifiers ?? 0
            let turboEnabled = binding.kind.supportsTurbo && binding.turboEnabled
            let turboRate = ButtonBindingSupport.clampTurboRate(binding.turboRate ?? ButtonBindingSupport.defaultTurboRate)
            let clutchDPI = binding.kind == .dpiClutch ? DeviceProfiles.clampDPI(binding.clutchDPI ?? ButtonBindingSupport.defaultBasiliskDPIClutchDPI, device: device) : nil
            guard try runUSBWrite({
                try setButtonBindingUSB(
                    $0,
                    device,
                    request: USBButtonBindingWrite(
                        slot: slot,
                        kind: kind,
                        hidKey: hidKey,
                        hidModifiers: hidModifiers,
                        turboEnabled: turboEnabled,
                        turboRate: turboRate,
                        clutchDPI: clutchDPI,
                        persistentProfile: binding.persistentProfile,
                        writePersistentLayer: binding.writePersistentLayer,
                        writeDirectLayer: binding.writeDirectLayer
                    )
                )
            }) else {
                throw BridgeError.commandFailed("Failed to set button binding")
            }
        }

        if options.readbackPolicy == .skipStateReadback,
           let cached = lastStateByDeviceID[device.id] {
            let projected = projectedState(from: cached, applying: patch, device: device)
            lastStateByDeviceID[device.id] = projected
            return projected
        }

        return try await readStateAfterUSBWrite(device: device)
    }

    private func applyUSBScalarSettings(
        device: MouseDevice,
        patch: DevicePatch,
        runUSBWrite: ((USBHIDControlSession) throws -> Bool) throws -> Bool
    ) throws {
        if let mode = patch.deviceMode {
            guard try runUSBWrite({ try setDeviceMode($0, device, mode: mode.mode, param: mode.param) }) else {
                throw BridgeError.commandFailed("Failed to set device mode")
            }
        }

        if let threshold = patch.lowBatteryThresholdRaw {
            guard try runUSBWrite({ try setLowBatteryThreshold($0, device, thresholdRaw: threshold) }) else {
                throw BridgeError.commandFailed("Failed to set low battery threshold")
            }
        }

        if device.supportsScrollModeControls {
            if let scrollMode = patch.scrollMode {
                guard try runUSBWrite({ try setScrollMode($0, device, mode: scrollMode) }) else {
                    throw BridgeError.commandFailed("Failed to set scroll mode")
                }
            }

            if let scrollAcceleration = patch.scrollAcceleration {
                guard try runUSBWrite({ try setScrollAcceleration($0, device, enabled: scrollAcceleration) }) else {
                    throw BridgeError.commandFailed("Failed to set scroll acceleration")
                }
            }

            if let scrollSmartReel = patch.scrollSmartReel {
                guard try runUSBWrite({ try setScrollSmartReel($0, device, enabled: scrollSmartReel) }) else {
                    throw BridgeError.commandFailed("Failed to set scroll smart reel")
                }
            }
        }

        if let pollRate = patch.pollRate {
            guard try runUSBWrite({ try setPollRate($0, device, value: pollRate) }) else {
                throw BridgeError.commandFailed("Failed to set poll rate")
            }
        }

        if let timeout = patch.sleepTimeout {
            guard try runUSBWrite({ try setIdleTime($0, device, seconds: timeout) }) else {
                throw BridgeError.commandFailed("Failed to set sleep timeout")
            }
        }
    }

    private func applyUSBDpiPatchIfNeeded(
        device: MouseDevice,
        patch: DevicePatch,
        runUSBWrite: ((USBHIDControlSession) throws -> Bool) throws -> Bool,
        readUSBCurrentDpiStages: () throws -> USBDpiStageSnapshot?,
        readUSBCurrentDpi: () throws -> (Int, Int)?
    ) async throws -> MouseState? {
        guard patch.affectsDpiStages else {
            return nil
        }

        let cachedState = lastStateByDeviceID[device.id]
        let cachedDpiStages = patch.isActiveStageOnly ? cachedState?.dpi_stages : nil
        let cachedStagePairs = cachedDpiStages?.pairs
        let cachedStageValues = cachedStagePairs?.map(\.x) ?? cachedDpiStages?.values
        let canResolveActiveOnlyFromCache = patch.isActiveStageOnly && !(cachedStageValues?.isEmpty ?? true)
        let current: USBDpiStageSnapshot? = canResolveActiveOnlyFromCache ? nil : try readUSBCurrentDpiStages()
        let stages = resolvedUSBStageValues(
            patch: patch,
            device: device,
            cachedStageValues: cachedStageValues,
            current: current
        )
        guard let stages, !stages.isEmpty else {
            throw BridgeError.commandFailed("Failed to resolve current DPI stages")
        }
        let resolvedStagePairs = resolvedUSBStagePairs(
            patch: patch,
            device: device,
            stages: stages,
            cachedStagePairs: cachedStagePairs,
            current: current
        )
        let active = patch.activeStage ?? cachedDpiStages?.active_stage ?? current?.active ?? 0
        let activeClamped = max(0, min(stages.count - 1, active))
        let livePair = resolvedStagePairs[activeClamped]
        logUSBDpiApply(
            USBDpiApplyLogContext(
                device: device,
                patch: patch,
                cachedDpiStages: cachedDpiStages,
                current: current,
                activeClamped: activeClamped,
                livePair: livePair,
                stages: stages
            )
        )

        if patch.isActiveStageOnly {
            return try await applyUSBActiveDpiOnly(
                USBActiveDpiOnlyApplyContext(
                    device: device,
                    patch: patch,
                    cachedState: cachedState,
                    activeClamped: activeClamped,
                    livePair: livePair
                ),
                runUSBWrite: runUSBWrite,
                readUSBCurrentDpi: readUSBCurrentDpi
            )
        }

        try applyUSBResolvedDpiStages(
            USBResolvedDpiStagesApplyContext(
                device: device,
                stages: stages,
                activeClamped: activeClamped,
                livePair: livePair,
                resolvedStagePairs: resolvedStagePairs,
                stageIDs: current?.stageIDs,
                usesProjectedReadback: device.usesProjectedDPIStageWriteReadback
            ),
            runUSBWrite: runUSBWrite,
            readUSBCurrentDpiStages: readUSBCurrentDpiStages,
            readUSBCurrentDpi: readUSBCurrentDpi
        )
        if device.usesProjectedDPIStageWriteReadback {
            let baseState: MouseState?
            if let cachedState {
                baseState = cachedState
            } else {
                baseState = try? await readState(device: device)
            }
            if let baseState {
                let projected = projectedState(from: baseState, applying: patch, device: device)
                lastStateByDeviceID[device.id] = projected
                return projected
            }
        }
        return nil
    }

    private func resolvedUSBStageValues(
        patch: DevicePatch,
        device: MouseDevice,
        cachedStageValues: [Int]?,
        current: USBDpiStageSnapshot?
    ) -> [Int]? {
        let rawValues = patch.dpiStagePairs?.map(\.x) ??
            patch.dpiStages ??
            cachedStageValues ??
            current?.values
        return rawValues?.map { DeviceProfiles.clampDPI($0, device: device) }
    }

    private func resolvedUSBStagePairs(
        patch: DevicePatch,
        device: MouseDevice,
        stages: [Int],
        cachedStagePairs: [DpiPair]?,
        current: USBDpiStageSnapshot?
    ) -> [DpiPair] {
        let pairs = Self.resolveDpiStagePairs(
            values: patch.dpiStages,
            pairs: patch.dpiStagePairs,
            fallbackPairs: cachedStagePairs ?? current?.pairs
        )?.map { pair in
            DpiPair(
                x: DeviceProfiles.clampDPI(pair.x, device: device),
                y: DeviceProfiles.clampDPI(pair.y, device: device)
            )
        }
        return pairs ?? stages.map { DpiPair(x: $0, y: $0) }
    }

    private func logUSBDpiApply(_ context: USBDpiApplyLogContext) {
        AppLog.debug(
            "Bridge",
            "apply usb dpi device=\(context.device.id) activeOnly=\(context.patch.isActiveStageOnly) " +
            "requestedActive=\(context.patch.activeStage.map(String.init) ?? "nil") " +
            "resolvedActive=\(context.activeClamped) livePair=(\(context.livePair.x),\(context.livePair.y)) " +
            "cachedActive=\(context.cachedDpiStages?.active_stage.map(String.init) ?? "nil") " +
            "currentActive=\(context.current?.active.description ?? "nil") " +
            "stages=\(context.stages.map(String.init).joined(separator: ","))"
        )
    }

    private func applyUSBActiveDpiOnly(
        _ context: USBActiveDpiOnlyApplyContext,
        runUSBWrite: ((USBHIDControlSession) throws -> Bool) throws -> Bool,
        readUSBCurrentDpi: () throws -> (Int, Int)?
    ) async throws -> MouseState {
        let device = context.device
        let livePair = context.livePair
        guard try runUSBWrite({ try setDPI($0, device, dpiX: livePair.x, dpiY: livePair.y, store: false) }) else {
            throw BridgeError.commandFailed("Failed to apply active DPI stage")
        }
        try verifyUSBLiveDpi(
            wanted: livePair,
            readUSBCurrentDpi: readUSBCurrentDpi,
            failureLogPrefix: "active-stage dpi mismatch"
        )
        AppLog.debug(
            "Bridge",
            "apply usb active-stage verified device=\(device.id) active=\(context.activeClamped) live=(\(livePair.x),\(livePair.y))"
        )
        let baseState: MouseState
        if let cachedState = context.cachedState {
            baseState = cachedState
        } else {
            baseState = try await readState(device: device)
        }
        let projected = projectedState(from: baseState, applying: context.patch, device: device)
        lastStateByDeviceID[device.id] = projected
        return projected
    }

    private func applyUSBResolvedDpiStages(
        _ context: USBResolvedDpiStagesApplyContext,
        runUSBWrite: ((USBHIDControlSession) throws -> Bool) throws -> Bool,
        readUSBCurrentDpiStages: () throws -> USBDpiStageSnapshot?,
        readUSBCurrentDpi: () throws -> (Int, Int)?
    ) throws {
        let device = context.device
        let livePair = context.livePair
        if context.stages.count == 1 {
            try applyUSBSingleDpiStage(
                device: device,
                livePair: livePair,
                stageIDs: context.stageIDs,
                runUSBWrite: runUSBWrite,
                readUSBCurrentDpi: readUSBCurrentDpi
            )
            return
        }

        guard try runUSBWrite({
            try setDPIStages(
                $0,
                device,
                stages: context.stages,
                activeStage: context.activeClamped,
                stagePairs: context.resolvedStagePairs,
                stageIDs: context.stageIDs
            )
        }) else {
            throw BridgeError.commandFailed("Failed to set DPI stages")
        }
        if context.usesProjectedReadback {
            // Basilisk V3 X HyperSpeed USB ACKs the stage-table write but can
            // immediately report the old one-slot table/live DPI. Project the
            // accepted write so profile switches do not collapse back to Base Profile.
            guard try runUSBWrite({ try setDPI($0, device, dpiX: livePair.x, dpiY: livePair.y, store: false) }) else {
                throw BridgeError.commandFailed("Failed to apply active DPI stage")
            }
            AppLog.debug(
                "Bridge",
                "usb dpi stage write projected device=\(device.id) stages=\(context.stages) active=\(context.activeClamped)"
            )
            return
        }
        try verifyUSBStageWrite(
            device: device,
            stages: context.stages,
            activeClamped: context.activeClamped,
            resolvedStagePairs: context.resolvedStagePairs,
            readUSBCurrentDpiStages: readUSBCurrentDpiStages
        )
        guard try runUSBWrite({ try setDPI($0, device, dpiX: livePair.x, dpiY: livePair.y, store: false) }) else {
            throw BridgeError.commandFailed("Failed to apply active DPI stage")
        }
        try verifyUSBLiveDpi(
            wanted: livePair,
            readUSBCurrentDpi: readUSBCurrentDpi,
            failureLogPrefix: "post-stage live dpi mismatch"
        )
    }

    private func applyUSBSingleDpiStage(
        device: MouseDevice,
        livePair: DpiPair,
        stageIDs: [UInt8]?,
        runUSBWrite: ((USBHIDControlSession) throws -> Bool) throws -> Bool,
        readUSBCurrentDpi: () throws -> (Int, Int)?
    ) throws {
        // Preserve single-stage table intent when the device accepts the stage-table command.
        do {
            _ = try runUSBWrite({
                try setDPIStages(
                    $0,
                    device,
                    stages: [livePair.x],
                    activeStage: 0,
                    stagePairs: [livePair],
                    stageIDs: stageIDs
                )
            })
        } catch {
            AppLog.debug("Bridge", "single-stage table persist failed: \(error.localizedDescription)")
        }

        guard try runUSBWrite({ try setDPI($0, device, dpiX: livePair.x, dpiY: livePair.y, store: false) }) else {
            throw BridgeError.commandFailed("Failed to set DPI")
        }
        guard let readback = try readUSBCurrentDpi(),
              readback.0 == livePair.x,
              readback.1 == livePair.y else {
            throw BridgeError.commandFailed("Failed to verify DPI write")
        }
    }

    private func verifyUSBStageWrite(
        device: MouseDevice,
        stages: [Int],
        activeClamped: Int,
        resolvedStagePairs: [DpiPair],
        readUSBCurrentDpiStages: () throws -> USBDpiStageSnapshot?
    ) throws {
        guard let readback = try readUSBCurrentDpiStages() else {
            throw BridgeError.commandFailed("Failed to verify DPI stage write")
        }
        let readbackActive = max(0, min(stages.count - 1, readback.active))
        let readbackValues = Array(readback.values.prefix(stages.count)).map { DeviceProfiles.clampDPI($0, device: device) }
        let readbackPairs = Array(readback.pairs.prefix(resolvedStagePairs.count)).map { pair in
            DpiPair(
                x: DeviceProfiles.clampDPI(pair.x, device: device),
                y: DeviceProfiles.clampDPI(pair.y, device: device)
            )
        }
        guard readbackPairs == resolvedStagePairs && readbackActive == activeClamped else {
            AppLog.error(
                "Bridge",
                "dpi stage verify mismatch wanted=\(stages) active=\(activeClamped) " +
                "got=\(readbackValues) active=\(readbackActive)"
            )
            throw BridgeError.commandFailed("Failed to verify DPI stage write")
        }
    }

    private func verifyUSBLiveDpi(
        wanted livePair: DpiPair,
        readUSBCurrentDpi: () throws -> (Int, Int)?,
        failureLogPrefix: String
    ) throws {
        let liveReadback = try readUSBCurrentDpi()
        guard liveReadback?.0 == livePair.x,
              liveReadback?.1 == livePair.y else {
            let actual = liveReadback.map { "(\($0.0),\($0.1))" } ?? "nil"
            AppLog.error("Bridge", "\(failureLogPrefix) wanted=(\(livePair.x),\(livePair.y)) got=\(actual)")
            throw BridgeError.commandFailed("Failed to verify active DPI stage")
        }
    }

    private func readStateAfterUSBWrite(device: MouseDevice) async throws -> MouseState {
        do {
            return try await readState(device: device)
        } catch {
            AppLog.error(
                "Bridge",
                "usb post-write readback failed device=\(device.id): \(error.localizedDescription)"
            )
            throw error
        }
    }

    nonisolated static func resolveDpiStagePairs(
        values: [Int]?,
        pairs: [DpiPair]?,
        fallbackPairs: [DpiPair]? = nil
    ) -> [DpiPair]? {
        if let pairs {
            return pairs
        }
        guard let values else {
            return fallbackPairs
        }
        if let fallbackPairs, fallbackPairs.count == values.count {
            return zip(values, fallbackPairs).map { value, fallbackPair in
                DpiPair(x: value, y: fallbackPair.y)
            }
        }
        return values.map { DpiPair(x: $0, y: $0) }
    }

    private func projectedState(from base: MouseState, applying patch: DevicePatch, device: MouseDevice) -> MouseState {
        let nextValues = (
            patch.dpiStagePairs?.map(\.x) ??
                patch.dpiStages ??
                base.dpi_stages.values
        )?.map { DeviceProfiles.clampDPI($0, device: device) }
        let nextPairs = Self.resolveDpiStagePairs(
            values: nextValues,
            pairs: patch.dpiStagePairs?.map { pair in
                DpiPair(
                    x: DeviceProfiles.clampDPI(pair.x, device: device),
                    y: DeviceProfiles.clampDPI(pair.y, device: device)
                )
            },
            fallbackPairs: base.dpi_stages.pairs
        )
        let requestedActive = patch.activeStage ?? base.dpi_stages.active_stage

        let resolvedActive: Int?
        if let values = nextValues, !values.isEmpty {
            resolvedActive = max(0, min(values.count - 1, requestedActive ?? 0))
        } else {
            resolvedActive = requestedActive
        }

        let nextDpi: DpiPair?
        if let nextPairs, !nextPairs.isEmpty {
            let activeIndex = max(0, min(nextPairs.count - 1, resolvedActive ?? 0))
            nextDpi = nextPairs[activeIndex]
        } else if let values = nextValues, !values.isEmpty {
            let activeIndex = max(0, min(values.count - 1, resolvedActive ?? 0))
            let value = values[activeIndex]
            nextDpi = DpiPair(x: value, y: value)
        } else {
            nextDpi = base.dpi
        }

        return MouseState(
            device: base.device,
            connection: base.connection,
            battery_percent: base.battery_percent,
            charging: base.charging,
            dpi: nextDpi,
            dpi_stages: DpiStages(active_stage: resolvedActive, values: nextValues, pairs: nextPairs),
            poll_rate: patch.pollRate ?? base.poll_rate,
            sleep_timeout: patch.sleepTimeout ?? base.sleep_timeout,
            device_mode: patch.deviceMode ?? base.device_mode,
            low_battery_threshold_raw: patch.lowBatteryThresholdRaw ?? base.low_battery_threshold_raw,
            scroll_mode: patch.scrollMode ?? base.scroll_mode,
            scroll_acceleration: patch.scrollAcceleration ?? base.scroll_acceleration,
            scroll_smart_reel: patch.scrollSmartReel ?? base.scroll_smart_reel,
            active_onboard_profile: base.active_onboard_profile,
            onboard_profile_count: base.onboard_profile_count,
            led_value: patch.ledBrightness ?? base.led_value,
            capabilities: base.capabilities
        )
    }
}

private extension DevicePatch {
    var isActiveStageOnly: Bool {
        guard activeStage != nil else { return false }
        if pollRate != nil { return false }
        if sleepTimeout != nil { return false }
        if deviceMode != nil { return false }
        if lowBatteryThresholdRaw != nil { return false }
        if scrollMode != nil { return false }
        if scrollAcceleration != nil { return false }
        if scrollSmartReel != nil { return false }
        if dpiStages != nil { return false }
        if dpiStagePairs != nil { return false }
        if ledBrightness != nil { return false }
        if ledRGB != nil { return false }
        if lightingEffect != nil { return false }
        if usbLightingZoneLEDIDs != nil { return false }
        if buttonBinding != nil { return false }
        if usbButtonProfileAction != nil { return false }
        return true
    }
}
