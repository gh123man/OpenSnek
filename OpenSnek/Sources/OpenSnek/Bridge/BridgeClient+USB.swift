import Foundation
import IOKit.hid
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

extension BridgeClient {
    struct USBRawButtonBindingWrite {
        let profile: UInt8
        let slot: UInt8
        let hypershift: UInt8
        let functionBlock: [UInt8]
    }

    struct USBButtonBindingWrite {
        let slot: Int
        let kind: String
        let hidKey: Int
        let hidModifiers: Int
        let turboEnabled: Bool
        let turboRate: Int
        let clutchDPI: Int?
        let persistentProfile: Int
        let writePersistentLayer: Bool
        let writeDirectLayer: Bool
    }

    static func usbButtonWriteSucceeded(
        writePersistentLayer: Bool,
        writeDirectLayer: Bool,
        wrotePersistent: Bool,
        wroteDirect: Bool
    ) -> Bool {
        if writePersistentLayer, !wrotePersistent {
            return false
        }
        if writeDirectLayer, !wroteDirect {
            return false
        }
        return writePersistentLayer || writeDirectLayer
    }

    func resolvedUSBStateCapabilities(
        profile: DeviceProfile?,
        stages: USBDpiStageSnapshot?,
        poll: Int?,
        sleepTimeout: Int?,
        led: Int?
    ) -> Capabilities {
        if profile != nil {
            return Capabilities(
                dpi_stages: true,
                poll_rate: true,
                power_management: true,
                button_remap: true,
                lighting: true
            )
        }

        return Capabilities(
            dpi_stages: stages != nil,
            poll_rate: poll != nil,
            power_management: sleepTimeout != nil,
            button_remap: false,
            lighting: led != nil
        )
    }

    func resolvedUSBStateCapabilities(
        profile: DeviceProfile?,
        stages: (Int, [Int])?,
        poll: Int?,
        sleepTimeout: Int?,
        led: Int?
    ) -> Capabilities {
        resolvedUSBStateCapabilities(
            profile: profile,
            stages: stages.map { active, values in
                USBDpiStageSnapshot(
                    active: active,
                    values: values,
                    pairs: values.map { DpiPair(x: $0, y: $0) },
                    stageIDs: Array(0..<values.count).map(UInt8.init)
                )
            },
            poll: poll,
            sleepTimeout: sleepTimeout,
            led: led
        )
    }

    func debugUSBReadButtonBinding(
        device: MouseDevice,
        slot: Int,
        profile: Int = 0x01,
        hypershift: Int = 0x00
    ) async throws -> [UInt8]? {
        guard device.transport != .bluetooth else { return nil }
        let sessions = sessionsFor(device: device)
        guard !sessions.isEmpty else {
            throw BridgeError.commandFailed("Device not available")
        }

        let clampedSlot = UInt8(max(0, min(255, slot)))
        let clampedProfile = UInt8(max(0, min(255, profile)))
        let clampedHypershift = UInt8(max(0, min(1, hypershift)))
        let session = sessions[0]
        if let block = try getButtonBindingUSBRaw(
            session,
            device,
            profile: clampedProfile,
            slot: clampedSlot,
            hypershift: clampedHypershift
        ) {
            deviceSessions[device.id] = session
            return block
        }
        return nil
    }

    func debugUSBSetButtonBindingRaw(
        device: MouseDevice,
        slot: Int,
        profile: Int = 0x01,
        hypershift: Int = 0x00,
        functionBlock: [UInt8]
    ) async throws -> Bool {
        guard device.transport != .bluetooth else { return false }
        guard functionBlock.count == 7 else {
            throw BridgeError.commandFailed("functionBlock must be exactly 7 bytes")
        }
        let sessions = sessionsFor(device: device)
        guard !sessions.isEmpty else {
            throw BridgeError.commandFailed("Device not available")
        }

        let clampedSlot = UInt8(max(0, min(255, slot)))
        let clampedProfile = UInt8(max(0, min(255, profile)))
        let clampedHypershift = UInt8(max(0, min(1, hypershift)))
        let session = sessions[0]
        if try setButtonBindingUSBRaw(
            session,
            device,
            request: USBRawButtonBindingWrite(
                profile: clampedProfile,
                slot: clampedSlot,
                hypershift: clampedHypershift,
                functionBlock: functionBlock
            )
        ) {
            deviceSessions[device.id] = session
            return true
        }
        return false
    }

    func readUSBState(device: MouseDevice, session: USBHIDControlSession) async throws -> MouseState {
        try session.withExclusiveDeviceAccess {
            // A cached session-level kIOReturnNotPermitted can be transient around sleep/wake.
            // Always attempt a fresh HID exchange here instead of trapping the process in a
            // self-sustaining permission loop until restart.
            guard let dpi = try getDPI(session, device) else {
                throw BridgeError.usbMouseUnavailable
            }

            let serial = try getSerial(session, device)
            let fw = try getFirmware(session, device)
            let mode = try getDeviceMode(session, device)
            let battery = try getBattery(session, device)
            let stages = try getDPIStageSnapshot(session, device)
            let poll = try getPollRate(session, device)
            let sleepTimeout = try getIdleTime(session, device)
            let onboardProfile = try getOnboardProfileInfo(session, device)
            let scrollProfileID = onboardProfile?.active ?? 1
            let lowBatteryThreshold = try getLowBatteryThreshold(session, device)
            let scrollMode: Int?
            let scrollAcceleration: Bool?
            let scrollSmartReel: Bool?
            if device.supportsScrollModeControls {
                scrollMode = try getScrollMode(session, device, profileID: scrollProfileID)
                scrollAcceleration = try getScrollAcceleration(session, device, profileID: scrollProfileID)
                scrollSmartReel = try getScrollSmartReel(session, device, profileID: scrollProfileID)
            } else {
                scrollMode = nil
                scrollAcceleration = nil
                scrollSmartReel = nil
            }
            let led = try getScrollLEDBrightness(session, device)
            let profile = usbDeviceProfile(for: device)
            let capabilities = resolvedUSBStateCapabilities(
                profile: profile,
                stages: stages,
                poll: poll,
                sleepTimeout: sleepTimeout,
                led: led
            )

            let active = stages.map {
                Self.resolvedUSBActiveStage(stages: $0, liveDpi: DpiPair(x: dpi.0, y: dpi.1))
            } ?? 0
            let values = stages?.values ?? [dpi.0]
            let pairs = stages?.pairs
            AppLog.debug(
                "Bridge",
                "readUSBState dpi-active-resolve device=\(device.id) " +
                "tableActive=\(stages?.active.description ?? "nil") live=(\(dpi.0),\(dpi.1)) " +
                "resolved=\(active) values=\(values.map(String.init).joined(separator: ","))"
            )
            AppLog.debug(
                "Bridge",
                "readUSBState scroll device=\(device.id) profile=\(scrollProfileID) " +
                "mode=\(scrollMode.map(String.init) ?? "nil") " +
                "accel=\(scrollAcceleration.map(String.init) ?? "nil") " +
                "smart=\(scrollSmartReel.map(String.init) ?? "nil")"
            )

            return MouseState(
                device: DeviceSummary(
                    id: device.id,
                    product_name: device.product_name,
                    serial: serial ?? device.serial,
                    transport: device.transport,
                    firmware: fw ?? device.firmware
                ),
                connection: "USB",
                battery_percent: battery?.0,
                charging: battery?.1,
                dpi: DpiPair(x: dpi.0, y: dpi.1),
                dpi_stages: DpiStages(active_stage: active, values: values, pairs: pairs),
                poll_rate: poll,
                sleep_timeout: sleepTimeout,
                device_mode: mode.map { DeviceMode(mode: $0.0, param: $0.1) },
                low_battery_threshold_raw: lowBatteryThreshold,
                scroll_mode: scrollMode,
                scroll_acceleration: scrollAcceleration,
                scroll_smart_reel: scrollSmartReel,
                active_onboard_profile: onboardProfile?.active,
                onboard_profile_count: onboardProfile?.count ?? max(1, device.onboard_profile_count),
                led_value: led,
                capabilities: capabilities
            )
        }
    }

    func usbControlAvailability(device: MouseDevice) async throws -> USBControlAvailability {
        guard device.transport == .usb else { return .unknown }

        try await deferUSBReconnectReadIfNeeded(deviceID: device.id, operation: "usb-control-availability")

        let orderedSessions = sessionsFor(device: device)
        guard !orderedSessions.isEmpty else {
            if managerAccessDenied {
                throw BridgeError.commandFailed(
                    "USB HID access denied by macOS. Enable Input Monitoring for OpenSnek " +
                    "(or Terminal/Xcode when running via swift run/Xcode), then relaunch."
                )
            }
            return .receiverAbsent
        }

        var firstError: Error?
        for (index, session) in orderedSessions.enumerated() {
            do {
                let isReachable = try session.withExclusiveDeviceAccess {
                    try getDPI(session, device) != nil
                }
                if isReachable {
                    if index > 0 {
                        deviceSessions[device.id] = session
                        AppLog.debug(
                            "Bridge",
                            "usbControlAvailability switched to alternate session index=\(index) device=\(device.id)"
                        )
                    }
                    return .receiverPresentMouseReachable
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
                if let bridgeError = error as? BridgeError,
                   case .commandFailed(let message) = bridgeError,
                   message.contains("USB HID access denied") {
                    throw error
                }
                AppLog.debug(
                    "Bridge",
                    "usbControlAvailability candidate index=\(index) failed device=\(device.id): \(error.localizedDescription)"
                )
            }
        }

        deviceSessions[device.id]?.invalidateCachedTransaction()
        if let firstError,
           !Self.isUSBTelemetryUnavailableError(firstError) {
            AppLog.debug(
                "Bridge",
                "usbControlAvailability treating feature-report failure as mouse unavailable " +
                "device=\(device.id): \(firstError.localizedDescription)"
            )
        }
        return .receiverPresentMouseUnavailable
    }

    func sessionFor(device: MouseDevice) -> USBHIDControlSession? {
        deviceSessions[device.id]
    }

    func sessionsFor(device: MouseDevice) -> [USBHIDControlSession] {
        if let preferred = deviceSessions[device.id] {
            let rest = (deviceSessionCandidates[device.id] ?? []).filter { $0 !== preferred }
            return [preferred] + rest
        }
        return deviceSessionCandidates[device.id] ?? []
    }

    func perform(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        classID: UInt8,
        cmdID: UInt8,
        size: UInt8,
        args: [UInt8] = [],
        responseAttempts: Int = 6,
        responseDelayUs: useconds_t = 30_000
    ) throws -> [UInt8]? {
#if DEBUG
        OpenSnekUITestSupport.recordUSBCommand(
            device: device,
            classID: classID,
            cmdID: cmdID,
            size: size,
            args: args
        )
#endif
        do {
            let response = try session.perform(
                classID: classID,
                cmdID: cmdID,
                size: size,
                args: args,
                transactionID: usbDeviceProfile(for: device)?.usbTransactionID,
                responseAttempts: responseAttempts,
                responseDelayUs: responseDelayUs
            )
            hidAccessDenied = false
            return response
        } catch let error as BridgeError {
            if case .commandFailed(let message) = error, message.contains("USB HID access denied") {
                hidAccessDenied = true
                let now = Date()
                if lastOpenDeniedLogAt == nil || now.timeIntervalSince(lastOpenDeniedLogAt!) > 2.0 {
                    AppLog.warning("Bridge", "USB HID access denied device=\(device.id); Input Monitoring is required")
                    lastOpenDeniedLogAt = now
                }
            }
            throw error
        }
    }

    func getDPI(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> (Int, Int)? {
        guard let r = try perform(session, device, classID: 0x04, cmdID: 0x85, size: 0x07, args: [0x00]), r[0] == 0x02 else { return nil }
        return (Int(r[9]) << 8 | Int(r[10]), Int(r[11]) << 8 | Int(r[12]))
    }

    func setDPI(_ session: USBHIDControlSession, _ device: MouseDevice, dpiX: Int, dpiY: Int, store: Bool) throws -> Bool {
        let x = DeviceProfiles.clampDPI(dpiX, device: device)
        let y = DeviceProfiles.clampDPI(dpiY, device: device)
        let storage: UInt8 = store ? 0x01 : 0x00
        let args: [UInt8] = [
            storage,
            UInt8((x >> 8) & 0xFF),
            UInt8(x & 0xFF),
            UInt8((y >> 8) & 0xFF),
            UInt8(y & 0xFF)
        ]
        guard let r = try perform(session, device, classID: 0x04, cmdID: 0x05, size: 0x07, args: args), r[0] == 0x02 else { return false }
        return true
    }

    func getDPIStageSnapshot(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> USBDpiStageSnapshot? {
        guard let r = try perform(session, device, classID: 0x04, cmdID: 0x86, size: 0x26),
              let snapshot = parseUSBDpiStageSnapshotResponse(r, device: device)
        else {
            return nil
        }
        return snapshot
    }

    func usbResolveStageIndex(activeRaw: Int, stageIDs: [UInt8], count: Int) -> Int {
        if let mapped = stageIDs.firstIndex(of: UInt8(activeRaw & 0xFF)) {
            return mapped
        }
        if activeRaw >= 1, activeRaw <= count {
            return activeRaw - 1
        }
        return max(0, min(count - 1, activeRaw))
    }

    func usbStageIDsForWrite(count: Int, stageIDs: [UInt8]?) -> [UInt8] {
        let clippedCount = DeviceProfiles.clampDpiStageCount(count)
        let defaultStageIDs = (0..<DeviceProfiles.maximumDpiStageCount).map(UInt8.init)
        var ids = Array((stageIDs ?? defaultStageIDs).prefix(clippedCount))
        while ids.count < clippedCount {
            ids.append(ids.last.map { $0 &+ 1 } ?? UInt8(ids.count))
        }
        return ids
    }

    func setDPIStages(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        stages: [Int],
        activeStage: Int,
        stagePairs: [DpiPair]? = nil,
        stageIDs: [UInt8]? = nil
    ) throws -> Bool {
        let clippedPairs = Array(
            (stagePairs ?? stages.map { DpiPair(x: $0, y: $0) }).prefix(DeviceProfiles.maximumDpiStageCount)
        ).map { pair in
            DpiPair(
                x: DeviceProfiles.clampDPI(pair.x, device: device),
                y: DeviceProfiles.clampDPI(pair.y, device: device)
            )
        }
        guard !clippedPairs.isEmpty else { return false }
        let activeClamped = max(0, min(clippedPairs.count - 1, activeStage))
        let writeStageIDs = usbStageIDsForWrite(count: clippedPairs.count, stageIDs: stageIDs)
        guard writeStageIDs.count == clippedPairs.count else { return false }

        var args = [UInt8](repeating: 0, count: 3 + clippedPairs.count * 7)
        args[0] = 0x01
        args[1] = writeStageIDs[activeClamped]
        args[2] = UInt8(clippedPairs.count)
        var off = 3
        for (i, pair) in clippedPairs.enumerated() {
            args[off] = writeStageIDs[i]
            args[off + 1] = UInt8((pair.x >> 8) & 0xFF)
            args[off + 2] = UInt8(pair.x & 0xFF)
            args[off + 3] = UInt8((pair.y >> 8) & 0xFF)
            args[off + 4] = UInt8(pair.y & 0xFF)
            off += 7
        }

        guard let r = try perform(session, device, classID: 0x04, cmdID: 0x06, size: 0x26, args: args) else { return false }
        return r[0] == 0x02
    }

    func parseUSBDpiStageSnapshotResponse(_ response: [UInt8], device: MouseDevice? = nil) -> USBDpiStageSnapshot? {
        guard response.count >= 12, response[0] == 0x02 else { return nil }

        // USB response layout for 0x04:0x86:
        //   response[8]  = storage
        //   response[9]  = active stage ID token
        //   response[10] = stage count
        //   response[11...] = stage rows (7 bytes each)
        let activeRaw = Int(response[9])
        let count = DeviceProfiles.clampDpiStageCount(Int(response[10]))
        var values: [Int] = []
        var pairs: [DpiPair] = []
        var stageIDs: [UInt8] = []

        for index in 0..<count {
            let offset = 11 + (index * 7)
            guard offset + 6 < response.count else { break }
            let stageID = response[offset]
            let dpiX = (Int(response[offset + 1]) << 8) | Int(response[offset + 2])
            let dpiY = (Int(response[offset + 3]) << 8) | Int(response[offset + 4])
            stageIDs.append(stageID)
            values.append(DeviceProfiles.clampDPI(dpiX, device: device))
            pairs.append(
                DpiPair(
                    x: DeviceProfiles.clampDPI(dpiX, device: device),
                    y: DeviceProfiles.clampDPI(dpiY, device: device)
                )
            )
        }

        guard !values.isEmpty else { return nil }

        while values.count < count {
            let fallback = pairs.last ?? DpiPair(x: values.last ?? 800, y: values.last ?? 800)
            values.append(fallback.x)
            pairs.append(fallback)
            stageIDs.append(stageIDs.last.map { $0 &+ 1 } ?? UInt8(stageIDs.count))
        }

        let active = usbResolveStageIndex(
            activeRaw: activeRaw,
            stageIDs: Array(stageIDs.prefix(count)),
            count: count
        )
        return USBDpiStageSnapshot(
            active: active,
            values: Array(values.prefix(count)),
            pairs: Array(pairs.prefix(count)),
            stageIDs: Array(stageIDs.prefix(count))
        )
    }

    func getPollRate(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> Int? {
        guard let r = try perform(session, device, classID: 0x00, cmdID: 0x85, size: 0x01), r[0] == 0x02 else { return nil }
        switch r[8] {
        case 0x01: return 1000
        case 0x02: return 500
        case 0x08: return 125
        default: return nil
        }
    }

    func setPollRate(_ session: USBHIDControlSession, _ device: MouseDevice, value: Int) throws -> Bool {
        let raw: UInt8
        switch value {
        case 1000: raw = 0x01
        case 500: raw = 0x02
        case 125: raw = 0x08
        default: return false
        }
        guard let r = try perform(session, device, classID: 0x00, cmdID: 0x05, size: 0x01, args: [raw]) else { return false }
        return r[0] == 0x02
    }

    func getIdleTime(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> Int? {
        guard let r = try perform(session, device, classID: 0x07, cmdID: 0x83, size: 0x02), r[0] == 0x02 else { return nil }
        return (Int(r[8]) << 8) | Int(r[9])
    }

    func setIdleTime(_ session: USBHIDControlSession, _ device: MouseDevice, seconds: Int) throws -> Bool {
        let clamped = max(60, min(900, seconds))
        let args: [UInt8] = [UInt8((clamped >> 8) & 0xFF), UInt8(clamped & 0xFF)]
        guard let r = try perform(session, device, classID: 0x07, cmdID: 0x03, size: 0x02, args: args) else { return false }
        return r[0] == 0x02
    }

    func getBattery(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> (Int, Bool)? {
        guard let r = try perform(session, device, classID: 0x07, cmdID: 0x80, size: 0x02), r[0] == 0x02 else { return nil }
        let charging = r[8] == 0x01
        let pct = Int((Double(r[9]) / 255.0) * 100.0)
        return (pct, charging)
    }

    func getSerial(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> String? {
        guard let r = try perform(session, device, classID: 0x00, cmdID: 0x82, size: 0x16), r[0] == 0x02 else { return nil }
        let raw = Data(r[8..<30])
        let s = String(data: raw, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
        return s?.isEmpty == false ? s : nil
    }

    func getFirmware(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> String? {
        guard let r = try perform(session, device, classID: 0x00, cmdID: 0x81, size: 0x02), r[0] == 0x02 else { return nil }
        return "\(r[8]).\(r[9])"
    }

    func getDeviceMode(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> (Int, Int)? {
        guard let r = try perform(session, device, classID: 0x00, cmdID: 0x84, size: 0x02), r[0] == 0x02 else { return nil }
        return (Int(r[8]), Int(r[9]))
    }

    func setDeviceMode(_ session: USBHIDControlSession, _ device: MouseDevice, mode: Int, param: Int = 0x00) throws -> Bool {
        let modeRaw: UInt8 = mode == 0x03 ? 0x03 : 0x00
        let args: [UInt8] = [modeRaw, UInt8(param & 0xFF)]
        guard let r = try perform(session, device, classID: 0x00, cmdID: 0x04, size: 0x02, args: args) else { return false }
        return r[0] == 0x02
    }

    func getLowBatteryThreshold(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> Int? {
        guard let r = try perform(session, device, classID: 0x07, cmdID: 0x81, size: 0x01), r[0] == 0x02 else { return nil }
        return Int(r[8])
    }

    func setLowBatteryThreshold(_ session: USBHIDControlSession, _ device: MouseDevice, thresholdRaw: Int) throws -> Bool {
        let clamped = UInt8(max(0x0C, min(0x3F, thresholdRaw)))
        guard let r = try perform(session, device, classID: 0x07, cmdID: 0x01, size: 0x01, args: [clamped]) else { return false }
        return r[0] == 0x02
    }

    func getScrollMode(_ session: USBHIDControlSession, _ device: MouseDevice, profileID: Int = 1) throws -> Int? {
        let args: [UInt8] = [UInt8(max(0, min(255, profileID))), 0x00]
        guard let r = try perform(session, device, classID: 0x02, cmdID: 0x94, size: 0x02, args: args), r[0] == 0x02 else { return nil }
        return Int(r[9])
    }

    func setScrollMode(_ session: USBHIDControlSession, _ device: MouseDevice, mode: Int, profileID: Int = 1) throws -> Bool {
        let modeRaw: UInt8 = mode == 1 ? 0x01 : 0x00
        let args: [UInt8] = [UInt8(max(0, min(255, profileID))), modeRaw]
        guard let r = try perform(session, device, classID: 0x02, cmdID: 0x14, size: 0x02, args: args) else { return false }
        return r[0] == 0x02
    }

    func getScrollAcceleration(_ session: USBHIDControlSession, _ device: MouseDevice, profileID: Int = 1) throws -> Bool? {
        let args: [UInt8] = [UInt8(max(0, min(255, profileID))), 0x00]
        guard let r = try perform(session, device, classID: 0x02, cmdID: 0x96, size: 0x02, args: args), r[0] == 0x02 else { return nil }
        return r[9] != 0
    }

    func setScrollAcceleration(_ session: USBHIDControlSession, _ device: MouseDevice, enabled: Bool, profileID: Int = 1) throws -> Bool {
        let args: [UInt8] = [UInt8(max(0, min(255, profileID))), enabled ? 0x01 : 0x00]
        guard let r = try perform(session, device, classID: 0x02, cmdID: 0x16, size: 0x02, args: args) else { return false }
        return r[0] == 0x02
    }

    func getScrollSmartReel(_ session: USBHIDControlSession, _ device: MouseDevice, profileID: Int = 1) throws -> Bool? {
        let args: [UInt8] = [UInt8(max(0, min(255, profileID))), 0x00]
        guard let r = try perform(session, device, classID: 0x02, cmdID: 0x97, size: 0x02, args: args), r[0] == 0x02 else { return nil }
        return r[9] != 0
    }

    func getOnboardProfileInfo(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> (active: Int, count: Int)? {
        guard device.onboard_profile_count > 1 else { return (active: 1, count: 1) }
        if let profile = usbDeviceProfile(for: device), profile.supportsMappedOnboardProfileCRUD {
            guard let inventoryResponse = try perform(session, device, classID: 0x05, cmdID: 0x81, size: 0x00),
                  let inventory = USBHIDProtocol.onboardProfileInventory(from: inventoryResponse) else {
                return nil
            }
            let active = try getDirectUSBActiveProfileID(session, device) ?? 1
            return (active: active, count: max(Int(inventory.maxProfileID), profile.onboardProfileCount))
        }
        guard let summary = try perform(session, device, classID: 0x00, cmdID: 0x87, size: 0x00), summary[0] == 0x02 else {
            return nil
        }
        let summaryActive = max(1, Int(summary[8]))
        let active = try getDirectUSBActiveProfileID(session, device) ?? summaryActive
        let count = max(1, Int(summary[10]))
        return (active: active, count: count)
    }

    func getDirectUSBActiveProfileID(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> Int? {
        guard device.profile_id == .basiliskV3Pro else { return nil }
        guard let response = try perform(session, device, classID: 0x05, cmdID: 0x84, size: 0x00),
              let active = USBHIDProtocol.activeProfileID(from: response) else {
            return nil
        }
        return max(1, Int(active))
    }

    func setScrollSmartReel(_ session: USBHIDControlSession, _ device: MouseDevice, enabled: Bool, profileID: Int = 1) throws -> Bool {
        let args: [UInt8] = [UInt8(max(0, min(255, profileID))), enabled ? 0x01 : 0x00]
        guard let r = try perform(session, device, classID: 0x02, cmdID: 0x17, size: 0x02, args: args) else { return false }
        return r[0] == 0x02
    }

    func usbDeviceProfile(for device: MouseDevice) -> DeviceProfile? {
        DeviceProfiles.resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport)
    }

    func usbLightingLEDIDs(for device: MouseDevice, override: [UInt8]? = nil) -> [UInt8] {
        let ids = override ?? usbDeviceProfile(for: device)?.allUSBLightingLEDIDs ?? [0x01]
        return ids.isEmpty ? [0x01] : ids
    }

    func getScrollLEDBrightness(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> Int? {
        var values: [Int] = []
        for ledID in usbLightingLEDIDs(for: device) {
            let args: [UInt8] = [0x01, ledID]
            guard let r = try perform(session, device, classID: 0x0F, cmdID: 0x84, size: 0x03, args: args), r[0] == 0x02 else {
                continue
            }
            values.append(Int(r[10]))
        }
        return values.max()
    }

    func setScrollLEDBrightness(_ session: USBHIDControlSession, _ device: MouseDevice, value: Int) throws -> Bool {
        let v = UInt8(max(0, min(255, value)))
        var wroteAny = false
        for ledID in usbLightingLEDIDs(for: device) {
            let args: [UInt8] = [0x01, ledID, v]
            guard let r = try perform(session, device, classID: 0x0F, cmdID: 0x04, size: 0x03, args: args), r[0] == 0x02 else {
                return false
            }
            wroteAny = true
        }
        return wroteAny
    }

    func setScrollLEDEffect(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        effect: LightingEffectPatch,
        ledIDs: [UInt8]? = nil
    ) throws -> Bool {
        var wroteAny = false
        for ledID in usbLightingLEDIDs(for: device, override: ledIDs) {
            let args = BLEVendorProtocol.buildScrollLEDEffectArgs(effect: effect, ledID: ledID)
            guard let r = try perform(
                session,
                device,
                classID: 0x0F,
                cmdID: 0x02,
                size: UInt8(max(0, min(255, args.count))),
                args: args
            ), r[0] == 0x02 else {
                return false
            }
            wroteAny = true
        }
        return wroteAny
    }

    func setUSBLightingCustomFrame(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        frame: USBLightingFramePatch
    ) throws -> Bool {
        let args = USBHIDProtocol.lightingCustomFrameArgs(
            storage: frame.storage,
            row: frame.row,
            startColumn: frame.startColumn,
            colors: frame.colors
        )
        guard let r = try perform(
            session,
            device,
            classID: 0x0F,
            cmdID: 0x03,
            size: UInt8(max(0, min(255, args.count))),
            args: args,
            responseAttempts: 8,
            responseDelayUs: 1_000
        ) else {
            return false
        }
        return r[0] == 0x02
    }

    func writeSoftwareLightingFrame(device: MouseDevice, frame: USBLightingFramePatch) async throws {
        guard device.transport == .usb,
              let layout = device.softwareLightingFrameLayout else {
            throw BridgeError.commandFailed("Software lighting frames are not supported for this device")
        }
        guard !frame.colors.isEmpty,
              frame.colors.count <= layout.cellCount else {
            throw BridgeError.commandFailed("Software lighting frame must contain 1...\(layout.cellCount) cells")
        }

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

        let session = orderedSessions[0]
        let succeeded = try session.withExclusiveDeviceAccess {
            try setUSBLightingCustomFrame(session, device, frame: frame)
        }
        guard succeeded else {
            throw BridgeError.commandFailed("Failed to write software lighting frame")
        }
        deviceSessions[device.id] = session
    }

    func writableUSBButtonSlots(for device: MouseDevice) -> [UInt8] {
        let layout = device.button_layout
        let slots = layout?.writableSlots ?? ButtonSlotDescriptor.defaults.map(\.slot)
        return slots.map { UInt8(max(0, min(255, $0))) }
    }

    func projectUSBButtonProfileToDirectLayer(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profile: UInt8
    ) throws -> Bool {
        let slots = writableUSBButtonSlots(for: device)
        guard !slots.isEmpty else { return false }

        for slot in slots {
            guard let block = try getButtonBindingUSBRaw(
                session,
                device,
                profile: profile,
                slot: slot,
                hypershift: 0x00
            ) else {
                return false
            }
            guard try setButtonBindingUSBRaw(
                session,
                device,
                request: USBRawButtonBindingWrite(
                    profile: 0x00,
                    slot: slot,
                    hypershift: 0x00,
                    functionBlock: block
                )
            ) else {
                return false
            }
        }

        return true
    }

    func duplicateUSBButtonProfile(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        sourceProfile: UInt8,
        targetProfile: UInt8
    ) throws -> Bool {
        let slots = writableUSBButtonSlots(for: device)
        guard !slots.isEmpty else { return false }

        for slot in slots {
            guard let block = try getButtonBindingUSBRaw(
                session,
                device,
                profile: sourceProfile,
                slot: slot,
                hypershift: 0x00
            ) else {
                return false
            }
            guard try setButtonBindingUSBRaw(
                session,
                device,
                request: USBRawButtonBindingWrite(
                    profile: targetProfile,
                    slot: slot,
                    hypershift: 0x00,
                    functionBlock: block
                )
            ) else {
                return false
            }
        }

        return true
    }

    func resetUSBButtonProfile(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profile: UInt8
    ) throws -> Bool {
        let slots = writableUSBButtonSlots(for: device)
        guard !slots.isEmpty else { return false }

        for slot in slots {
            guard let block = ButtonBindingSupport.defaultUSBFunctionBlock(
                for: Int(slot),
                profileID: device.profile_id
            ) else {
                return false
            }
            guard try setButtonBindingUSBRaw(
                session,
                device,
                request: USBRawButtonBindingWrite(
                    profile: profile,
                    slot: slot,
                    hypershift: 0x00,
                    functionBlock: block
                )
            ) else {
                return false
            }
        }

        return true
    }

    func setButtonBindingUSBRaw(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        request: USBRawButtonBindingWrite
    ) throws -> Bool {
        guard request.functionBlock.count == 7 else { return false }
        let args = [request.profile, request.slot, request.hypershift] + request.functionBlock
        guard let r = try perform(
            session,
            device,
            classID: 0x02,
            cmdID: 0x0C,
            size: UInt8(args.count),
            args: args,
            responseAttempts: 12,
            responseDelayUs: 40_000
        ) else { return false }
        return r[0] == 0x02
    }

    func setButtonBindingUSB(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        request: USBButtonBindingWrite
    ) throws -> Bool {
        guard let bindingKind = ButtonBindingKind(rawValue: request.kind) else { return false }
        let functionBlock = ButtonBindingSupport.buildUSBFunctionBlock(
            slot: request.slot,
            kind: bindingKind,
            hidKey: request.hidKey,
            hidModifiers: request.hidModifiers,
            turboEnabled: request.turboEnabled && bindingKind.supportsTurbo,
            turboRate: request.turboRate,
            clutchDPI: request.clutchDPI,
            profileID: device.profile_id
        )
        let clampedSlot = UInt8(max(0, min(255, request.slot)))

        let clampedPersistentProfile = UInt8(
            OnboardProfileLimits.clampPersistentProfileID(request.persistentProfile)
        )

        let wrotePersistent: Bool
        if request.writePersistentLayer {
            wrotePersistent = try setButtonBindingUSBRaw(
                session,
                device,
                request: USBRawButtonBindingWrite(
                    profile: clampedPersistentProfile,
                    slot: clampedSlot,
                    hypershift: 0x00,
                    functionBlock: functionBlock
                )
            )
            guard wrotePersistent else { return false }
        } else {
            wrotePersistent = false
        }
        let wroteDirect: Bool
        if request.writeDirectLayer {
            wroteDirect = try setButtonBindingUSBRaw(
                session,
                device,
                request: USBRawButtonBindingWrite(
                    profile: 0x00,
                    slot: clampedSlot,
                    hypershift: 0x00,
                    functionBlock: functionBlock
                )
            )
        } else {
            wroteDirect = false
        }
        return Self.usbButtonWriteSucceeded(
            writePersistentLayer: request.writePersistentLayer,
            writeDirectLayer: request.writeDirectLayer,
            wrotePersistent: wrotePersistent,
            wroteDirect: wroteDirect
        )
    }

    func getButtonBindingUSBRaw(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profile: UInt8,
        slot: UInt8,
        hypershift: UInt8
    ) throws -> [UInt8]? {
        var args: [UInt8] = [profile, slot, hypershift]
        args.append(contentsOf: [UInt8](repeating: 0x00, count: 7))
        guard let response = try perform(
            session,
            device,
            classID: 0x02,
            cmdID: 0x8C,
            size: UInt8(args.count),
            args: args,
            responseAttempts: 12,
            responseDelayUs: 40_000
        ), response[0] == 0x02 else {
            return nil
        }

        return ButtonBindingSupport.extractUSBFunctionBlock(
            response: response,
            profile: profile,
            slot: slot,
            hypershift: hypershift,
            profileID: device.profile_id
        )
    }
}
