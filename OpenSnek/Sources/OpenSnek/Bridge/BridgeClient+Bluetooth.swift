import Foundation
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

/// Adds Bluetooth behavior to `BridgeClient`.
extension BridgeClient {
    /// Stores Bluetooth battery state.
    struct BluetoothBatteryState: Equatable {
        let percent: Int?
        let charging: Bool?
    }

    func isBluetoothV3ProLightingDevice(_ device: MouseDevice) -> Bool {
        device.transport == .bluetooth &&
            (device.profile_id == .basiliskV3Pro || device.product_id == 0x00AC)
    }

    func bluetoothLightingLEDIDs(device: MouseDevice, override: [UInt8]? = nil) -> [UInt8] {
        let profileLEDIDs = DeviceProfiles
            .resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport)?
            .lightingLEDIDs()
        let raw = override ?? profileLEDIDs ?? [0x01]
        var seen: Set<UInt8> = []
        let ids = raw.filter { seen.insert($0).inserted }
        return ids.isEmpty ? [0x01] : ids
    }

    func formatLightingZoneValues(_ values: [(UInt8, Int)]) -> String {
        values
            .map { ledID, value in
                "0x\(String(format: "%02x", ledID))=\(value)"
            }
            .joined(separator: ",")
    }

    func formatLightingZoneColors(_ values: [(UInt8, RGBPatch)]) -> String {
        values
            .map { ledID, color in
                "0x\(String(format: "%02x", ledID))=(\(color.r),\(color.g),\(color.b))"
            }
            .joined(separator: ",")
    }

    func btHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    func btKeyLabel(_ key: BLEVendorProtocol.Key) -> String {
        btHex(Data(key.bytes))
    }

    func btNotifySummary(_ notifies: [Data]) -> String {
        notifies
            .map(btHex)
            .joined(separator: " | ")
    }

    static func resolveBluetoothBatteryState(
        device: MouseDevice,
        vendorRaw: Int?,
        vendorStatus: Int?,
        usbFallback: (Int, Bool)?
    ) -> BluetoothBatteryState {
        let vendorPercent = vendorRaw.map { raw in
            raw <= 100 ? raw : Int((Double(raw) / 255.0) * 100.0)
        }
        let charging: Bool?
        if device.transport == .bluetooth,
           device.profile_id == .basiliskV3XHyperspeed || device.product_id == 0x00BA {
            charging = false
        } else if device.transport == .bluetooth,
                  device.profile_id == .orochiV2 || device.product_id == 0x0095 {
            charging = false
        } else if device.transport == .bluetooth,
                  device.profile_id == .basiliskV3Pro || device.product_id == 0x00AC {
            charging = usbFallback?.1
        } else {
            charging = vendorStatus.map { $0 == 1 } ?? usbFallback?.1
        }

        return BluetoothBatteryState(
            percent: vendorPercent ?? usbFallback?.0,
            charging: charging
        )
    }

    func btGetLightingValue(device: MouseDevice, ledIDs: [UInt8]? = nil) async throws -> Int? {
        if isBluetoothV3ProLightingDevice(device) {
            let ids = bluetoothLightingLEDIDs(device: device, override: ledIDs)
            var values: [(UInt8, Int)] = []
            for ledID in ids {
                if let value = try await btGetScalar(device: device, key: .lightingBrightnessGet(ledID: ledID), size: 1) {
                    values.append((ledID, value))
                }
            }
            guard let first = values.first?.1 else { return nil }
            if values.contains(where: { $0.1 != first }) {
                AppLog.debug(
                    "Bridge",
                    "btGetLightingValue zone-mismatch device=\(device.id) values=\(formatLightingZoneValues(values))"
                )
            }
            return first
        }

        return try await btGetScalar(device: device, key: .lightingGet, size: 1)
    }

    func btReadLightingColor(device: MouseDevice, ledID: UInt8) async throws -> RGBPatch? {
        let key: BLEVendorProtocol.Key
        if isBluetoothV3ProLightingDevice(device) {
            key = .lightingZoneStateGet(ledID: ledID)
        } else {
            key = .lightingFrameGet
        }

        let req = nextBTReq()
        let header = BLEVendorProtocol.buildReadHeader(req: req, key: key)
        let notifies = try await btExchange([header], timeout: 0.6, device: device)
        guard let payload = BLEVendorProtocol.parsePayloadFrames(notifies: notifies, req: req) else {
            AppLog.debug(
                "Bridge",
                "btReadLightingColor no-payload device=\(device.id) led=0x\(String(format: "%02x", ledID)) req=\(req) notifies=\(btNotifySummary(notifies))"
            )
            return nil
        }
        let parsed = parseLightingRGB(payload: payload)
        if let parsed {
            AppLog.debug(
                "Bridge",
                "btReadLightingColor device=\(device.id) led=0x\(String(format: "%02x", ledID)) rgb=(\(parsed.r),\(parsed.g),\(parsed.b))"
            )
        } else {
            AppLog.debug(
                "Bridge",
                "btReadLightingColor parse-failed device=\(device.id) led=0x\(String(format: "%02x", ledID)) payload=\(btHex(payload))"
            )
        }
        return parsed
    }

    func readBluetoothState(device: MouseDevice, session: USBHIDControlSession?) async throws -> MouseState {
        let supportsLighting = device.showsLightingControls
        let profile = DeviceProfiles.resolve(
            vendorID: device.vendor_id,
            productID: device.product_id,
            transport: device.transport
        )
        let supportsMappedOnboardProfiles = profile?.supportsMappedOnboardProfileCRUD == true
        let btStages: BLEVendorProtocol.DpiStagesRead?
        if supportsMappedOnboardProfiles {
            btStages = lastStateByDeviceID[device.id].flatMap { state in
                guard let values = state.dpi_stages.values, !values.isEmpty else { return nil }
                let active = max(0, min(values.count - 1, state.dpi_stages.active_stage ?? 0))
                let pairs = state.dpi_stages.pairs ?? values.map { DpiPair(x: $0, y: $0) }
                return BLEVendorProtocol.DpiStagesRead(
                    active: active,
                    count: values.count,
                    values: values,
                    pairs: pairs,
                    marker: 0x03
                )
            }
        } else {
            btStages = (try? await btGetDpiStages(device: device))
                ?? btDpiSnapshotByDeviceID[device.id].map { snapshot in
                    BLEVendorProtocol.DpiStagesRead(
                        active: snapshot.active,
                        count: snapshot.count,
                        values: Array(snapshot.slots.prefix(snapshot.count)),
                        pairs: Array(snapshot.pairs.prefix(snapshot.count)),
                        marker: snapshot.marker
                    )
                }
        }
        let shouldPollGenericTelemetry = Self.shouldPollBluetoothGenericTelemetryForReadState(
            supportsMappedOnboardProfiles: supportsMappedOnboardProfiles
        )
        let batteryRaw: Int?
        let batteryStatus: Int?
        let lighting: Int?
        let sleepTimeout: Int?
        if !shouldPollGenericTelemetry {
            batteryRaw = nil
            batteryStatus = nil
            lighting = nil
            sleepTimeout = nil
        } else {
            batteryRaw = (try? await btGetScalar(device: device, key: .batteryRaw, size: 1)) ?? nil
            batteryStatus = (try? await btGetScalar(device: device, key: .batteryStatus, size: 1)) ?? nil
            lighting = supportsLighting ? (try? await btGetLightingValue(device: device)) : nil
            sleepTimeout = (try? await btGetScalar(device: device, key: .powerTimeoutGet, size: 2)) ?? nil
        }
        let activeOnboardProfile = profile?.supportsMappedOnboardProfileCRUD == true
            ? (try? await btReadActiveOnboardProfileID(device: device)) ?? nil
            : nil

        let usbBatteryFallback = session.flatMap { try? getBattery($0, device) }
        let batteryState = Self.resolveBluetoothBatteryState(
            device: device,
            vendorRaw: batteryRaw,
            vendorStatus: batteryStatus,
            usbFallback: usbBatteryFallback
        )

        return MouseState(
            device: DeviceSummary(
                id: device.id,
                product_name: device.product_name,
                serial: device.serial,
                transport: device.transport,
                firmware: nil
            ),
            connection: "Bluetooth",
            battery_percent: batteryState.percent,
            charging: batteryState.charging,
            dpi: {
                guard
                    let active = btStages?.active,
                    let values = btStages?.values,
                    active >= 0,
                    active < values.count
                else { return nil }
                if let pairs = btStages?.pairs, active < pairs.count {
                    return pairs[active]
                }
                let value = values[active]
                return DpiPair(x: value, y: value)
            }(),
            dpi_stages: DpiStages(active_stage: btStages?.active, values: btStages?.values, pairs: btStages?.pairs),
            poll_rate: nil,
            sleep_timeout: sleepTimeout,
            device_mode: nil,
            active_onboard_profile: activeOnboardProfile,
            onboard_profile_count: profile?.supportsMappedOnboardProfileCRUD == true ? profile?.onboardProfileCount : nil,
            led_value: lighting,
            capabilities: Capabilities(
                dpi_stages: true,
                poll_rate: false,
                power_management: true,
                button_remap: true,
                lighting: supportsLighting
            )
        )
    }

    nonisolated static func shouldPollBluetoothGenericTelemetryForReadState(
        supportsMappedOnboardProfiles: Bool
    ) -> Bool {
        !supportsMappedOnboardProfiles
    }

    func buildBluetoothDeltaState(
        device: MouseDevice,
        includeDpi: Bool,
        includeLighting: Bool,
        includePower: Bool
    ) async throws -> MouseState {
        let supportsLighting = device.showsLightingControls
        let btStages: BLEVendorProtocol.DpiStagesRead?
        if includeDpi {
            btStages = try await btGetDpiStages(device: device)
        } else {
            btStages = nil
        }

        let lighting: Int?
        if includeLighting, supportsLighting {
            lighting = try await btGetLightingValue(device: device)
        } else {
            lighting = nil
        }

        let sleepTimeout: Int?
        if includePower {
            sleepTimeout = try await btGetScalar(device: device, key: .powerTimeoutGet, size: 2)
        } else {
            sleepTimeout = nil
        }

        let dpiPair: DpiPair? = {
            guard
                let active = btStages?.active,
                let values = btStages?.values,
                active >= 0,
                active < values.count
            else { return nil }
            if let pairs = btStages?.pairs, active < pairs.count {
                return pairs[active]
            }
            let value = values[active]
            return DpiPair(x: value, y: value)
        }()

        return MouseState(
            device: DeviceSummary(
                id: device.id,
                product_name: device.product_name,
                serial: device.serial,
                transport: device.transport,
                firmware: nil
            ),
            connection: "Bluetooth",
            battery_percent: nil,
            charging: nil,
            dpi: dpiPair,
            dpi_stages: DpiStages(active_stage: btStages?.active, values: btStages?.values, pairs: btStages?.pairs),
            poll_rate: nil,
            sleep_timeout: sleepTimeout,
            device_mode: nil,
            led_value: lighting,
            capabilities: Capabilities(
                dpi_stages: true,
                poll_rate: false,
                power_management: true,
                button_remap: true,
                lighting: supportsLighting
            )
        )
    }

    func nextBTReq() -> UInt8 {
        defer { btReqID = btReqID &+ 1 }
        return btReqID
    }

    func btExchange(
        _ writes: [Data],
        timeout: TimeInterval = 0.8,
        device: MouseDevice? = nil,
        preferredPeripheralName: String? = nil
    ) async throws -> [Data] {
        let start = Date()
        await btAcquireExchangeLock()
        defer { btReleaseExchangeLock() }

        let result = try await btVendorClient.run(
            writes: writes,
            timeout: timeout,
            preferredPeripheralName: preferredPeripheralName ?? device?.product_name
        )
        AppLog.debug(
            "Bridge",
            "btExchange writes=\(writes.count) timeout=\(String(format: "%.2f", timeout))s " +
            "notifies=\(result.count) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s"
        )
        return result
    }

    func btAcquireExchangeLock() async {
        if !btExchangeLocked {
            btExchangeLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            btExchangeWaiters.append(continuation)
        }
    }

    func btReleaseExchangeLock() {
        if btExchangeWaiters.isEmpty {
            btExchangeLocked = false
            return
        }
        let next = btExchangeWaiters.removeFirst()
        next.resume()
    }

    func btGetScalar(device: MouseDevice, key: BLEVendorProtocol.Key, size: Int) async throws -> Int? {
        let req = nextBTReq()
        let header = BLEVendorProtocol.buildReadHeader(req: req, key: key)
        let notifies = try await btExchange([header], timeout: 0.5, device: device)
        guard let payload = BLEVendorProtocol.parsePayloadFrames(notifies: notifies, req: req) else {
            AppLog.debug(
                "Bridge",
                "btGetScalar no-payload device=\(device.id) key=\(btKeyLabel(key)) req=\(req) notifies=\(btNotifySummary(notifies))"
            )
            return nil
        }
        guard payload.count >= size else {
            AppLog.debug(
                "Bridge",
                "btGetScalar short-payload device=\(device.id) key=\(btKeyLabel(key)) req=\(req) " +
                "expected=\(size) actual=\(payload.count) payload=\(btHex(payload)) notifies=\(btNotifySummary(notifies))"
            )
            return nil
        }
        return payload.prefix(size).enumerated().reduce(0) { partial, pair in
            partial | (Int(pair.element) << (pair.offset * 8))
        }
    }

    func btSetScalar(device: MouseDevice, key: BLEVendorProtocol.Key, value: Int, size: Int, payloadLength: UInt8) async throws -> Bool {
        let req = nextBTReq()
        let header = BLEVendorProtocol.buildWriteHeader(req: req, payloadLength: payloadLength, key: key)
        let payload = Data((0..<size).map { idx in UInt8((value >> (8 * idx)) & 0xFF) })
        let notifies = try await btExchange([header, payload], timeout: 0.9, device: device)
        return btAckSuccess(notifies: notifies, req: req)
    }

    func btAckSuccess(notifies: [Data], req: UInt8) -> Bool {
        for frame in notifies {
            guard let header = BLEVendorProtocol.NotifyHeader(data: frame) else { continue }
            if header.req == req {
                return header.status == 0x02
            }
        }
        return false
    }

    func btGetDpiStages(device: MouseDevice) async throws -> BLEVendorProtocol.DpiStagesRead? {
        let req = nextBTReq()
        let header = BLEVendorProtocol.buildReadHeader(req: req, key: .dpiStagesGet)
        let notifies = try await btExchange([header], timeout: 0.6, device: device)
        guard let payload = BLEVendorProtocol.parsePayloadFrames(notifies: notifies, req: req) else {
            AppLog.debug(
                "Bridge",
                "btGetDpiStages no-payload device=\(device.id) req=\(req) notifies=\(btNotifySummary(notifies))"
            )
            return nil
        }
        guard let parsed = BLEVendorProtocol.parseDpiStages(blob: payload) else {
            AppLog.debug(
                "Bridge",
                "btGetDpiStages parse-failed device=\(device.id) req=\(req) " +
                "payload=\(btHex(payload)) notifies=\(btNotifySummary(notifies))"
            )
            return nil
        }

        let dpiRange = DeviceProfiles.dpiRange(for: device)
        guard !parsed.values.isEmpty,
              parsed.active >= 0,
              parsed.active < parsed.values.count,
              parsed.values.allSatisfy({ dpiRange.contains($0) }) else {
            AppLog.debug(
                "Bridge",
                "btGetDpiStages ignored invalid payload device=\(device.id) values=\(parsed.values) active=\(parsed.active)"
            )
            return nil
        }

        if var expected = btExpectedDpiByDeviceID[device.id] {
            let parsedValues = Array(parsed.values.prefix(expected.values.count))
            let parsedPairs = Array(parsed.pairs.prefix(expected.pairs.count))
            if parsed.active == expected.active && parsedPairs == expected.pairs {
                btExpectedDpiByDeviceID[device.id] = nil
            } else if Date() < expected.expiresAt,
                      expected.remainingMasks > 0,
                      Self.shouldMaskBluetoothExpectedRead(
                        parsedActive: parsed.active,
                        parsedValues: parsed.values,
                        parsedPairs: parsed.pairs,
                        expected: expected
                      ) {
                expected.remainingMasks -= 1
                btExpectedDpiByDeviceID[device.id] = expected
                AppLog.debug(
                    "Bridge",
                    "btGetDpiStages stale-read masked device=\(device.id) expectedActive=\(expected.active) expectedValues=\(expected.values) " +
                    "actualActive=\(parsed.active) actualValues=\(parsedValues) remainingMasks=\(expected.remainingMasks)"
                )
                return BLEVendorProtocol.DpiStagesRead(
                    active: expected.active,
                    count: expected.values.count,
                    values: expected.values,
                    pairs: expected.pairs,
                    marker: parsed.marker
                )
            } else {
                btExpectedDpiByDeviceID[device.id] = nil
            }
        }

        if let snap = BLEVendorProtocol.parseDpiStageSnapshot(blob: payload) {
            btDpiSnapshotByDeviceID[device.id] = snap
        }
        AppLog.debug("Bridge", "btGetDpiStages device=\(device.id) active=\(parsed.active) values=\(parsed.values)")
        return parsed
    }

    func btGetDpiStageSnapshot(device: MouseDevice) async throws -> BLEVendorProtocol.DpiStageSnapshot? {
        let req = nextBTReq()
        let header = BLEVendorProtocol.buildReadHeader(req: req, key: .dpiStagesGet)
        let notifies = try await btExchange([header], timeout: 0.6, device: device)
        guard let payload = BLEVendorProtocol.parsePayloadFrames(notifies: notifies, req: req) else {
            AppLog.debug(
                "Bridge",
                "btGetDpiStageSnapshot no-payload device=\(device.id) req=\(req) notifies=\(btNotifySummary(notifies))"
            )
            return nil
        }
        guard let parsed = BLEVendorProtocol.parseDpiStageSnapshot(blob: payload) else {
            AppLog.debug(
                "Bridge",
                "btGetDpiStageSnapshot parse-failed device=\(device.id) req=\(req) payload=\(btHex(payload)) " +
                "notifies=\(btNotifySummary(notifies))"
            )
            return nil
        }
        btDpiSnapshotByDeviceID[device.id] = parsed
        return parsed
    }

    func btSetDpiStages(device: MouseDevice, active: Int, values: [Int], pairs: [DpiPair]? = nil) async throws -> Bool {
        let current: BLEVendorProtocol.DpiStageSnapshot?
        if let cached = btDpiSnapshotByDeviceID[device.id] {
            current = cached
        } else {
            current = try await btGetDpiStageSnapshot(device: device)
        }
        let marker = current?.marker ?? 0x03
        let count = DeviceProfiles.clampDpiStageCount(values.count)
        let currentPairs = current?.pairs ?? [
            DpiPair(x: 800, y: 800),
            DpiPair(x: 1600, y: 1600),
            DpiPair(x: 2400, y: 2400),
            DpiPair(x: 3200, y: 3200),
            DpiPair(x: 6400, y: 6400)
        ]
        let defaultStageIDs = (1...DeviceProfiles.maximumDpiStageCount).map(UInt8.init)
        let currentStageIDs = Array((current?.stageIDs ?? defaultStageIDs).prefix(DeviceProfiles.maximumDpiStageCount))
        let requestedPairs = pairs ?? values.map { DpiPair(x: $0, y: $0) }
        let mergedPairs = BLEVendorProtocol.mergedStagePairs(
            currentPairs: currentPairs,
            requestedCount: count,
            requestedPairs: requestedPairs
        )

        let payload = BLEVendorProtocol.buildDpiStagePayload(
            active: active,
            count: count,
            pairs: mergedPairs,
            marker: marker,
            stageIDs: currentStageIDs
        )
        let req = nextBTReq()
        let header = BLEVendorProtocol.buildWriteHeader(req: req, payloadLength: 0x26, key: .dpiStagesSet)
        let notifies = try await btExchange([header, payload.prefix(20), payload.suffix(from: 20)], timeout: 0.9, device: device)
        let ok = btAckSuccess(notifies: notifies, req: req)
        AppLog.debug("Bridge", "btSetDpiStages device=\(device.id) reqActive=\(active) reqValues=\(values) count=\(count) ok=\(ok)")
        if ok {
            let previousSnapshot = btDpiSnapshotByDeviceID[device.id]
            let expectedActive = max(0, min(count - 1, active))
            let expectedPairs = Array(mergedPairs.prefix(count))
            let expectedValues = expectedPairs.map(\.x)
            btDpiSnapshotByDeviceID[device.id] = BLEVendorProtocol.DpiStageSnapshot(
                active: expectedActive,
                count: count,
                slots: mergedPairs.map(\.x),
                pairs: mergedPairs,
                stageIDs: currentStageIDs,
                marker: marker
            )
            btExpectedDpiByDeviceID[device.id] = BluetoothExpectedDpiState(
                active: expectedActive,
                values: expectedValues,
                pairs: expectedPairs,
                previousActive: previousSnapshot?.active,
                previousValues: previousSnapshot.map { Array($0.slots.prefix($0.count)) },
                previousPairs: previousSnapshot.map { Array($0.pairs.prefix($0.count)) },
                expiresAt: Date().addingTimeInterval(1.2),
                remainingMasks: 4
            )
        }
        return ok
    }

    func btSetLightingValue(device: MouseDevice, value: Int) async throws -> Bool {
        let clamped = max(0, min(255, value))
        if isBluetoothV3ProLightingDevice(device) {
            var wroteAny = false
            for ledID in bluetoothLightingLEDIDs(device: device) {
                let wrote = try await btSetScalar(
                    device: device,
                    key: .lightingBrightnessSet(ledID: ledID),
                    value: clamped,
                    size: 1,
                    payloadLength: 0x01
                )
                guard wrote else { return false }
                wroteAny = true
            }
            return wroteAny
        }

        return try await btSetScalar(
            device: device,
            key: .lightingSet,
            value: clamped,
            size: 1,
            payloadLength: 0x01
        )
    }

    func btSetLightingRGB(device: MouseDevice, r: Int, g: Int, b: Int, ledIDs: [UInt8]? = nil) async throws -> Bool {
        if isBluetoothV3ProLightingDevice(device) {
            let payload = BLEVendorProtocol.buildV3ProLightingZoneStatePayload(r: r, g: g, b: b)
            var wroteAny = false
            for ledID in bluetoothLightingLEDIDs(device: device, override: ledIDs) {
                let req = nextBTReq()
                let header = BLEVendorProtocol.buildWriteHeader(
                    req: req,
                    payloadLength: UInt8(payload.count),
                    key: .lightingZoneStateSet(ledID: ledID)
                )
                let notifies = try await btExchange([header, payload], timeout: 0.9, device: device)
                guard btAckSuccess(notifies: notifies, req: req) else { return false }
                wroteAny = true
            }
            return wroteAny
        }

        let payload = Data([
            0x04, 0x00, 0x00, 0x00,
            0x00,
            UInt8(max(0, min(255, r))),
            UInt8(max(0, min(255, g))),
            UInt8(max(0, min(255, b)))
        ])
        let req = nextBTReq()
        let header = BLEVendorProtocol.buildWriteHeader(req: req, payloadLength: 0x08, key: .lightingFrameSet)
        let notifies = try await btExchange([header, payload], timeout: 0.9, device: device)
        return btAckSuccess(notifies: notifies, req: req)
    }

    func btApplyLightingEffectFallback(device: MouseDevice, effect: LightingEffectPatch, ledIDs: [UInt8]? = nil) async throws -> Bool {
        switch effect.kind {
        case .off:
            return try await btSetLightingValue(device: device, value: 0)
        case .staticColor:
            return try await btSetLightingRGB(
                device: device,
                r: effect.primary.r,
                g: effect.primary.g,
                b: effect.primary.b,
                ledIDs: ledIDs
            )
        case .spectrum, .wave, .reactive, .pulseRandom, .pulseSingle, .pulseDual:
            return false
        }
    }

    func parseLightingRGB(payload: Data) -> RGBPatch? {
        guard !payload.isEmpty else { return nil }

        if let zoneState = BLEVendorProtocol.parseV3ProLightingZoneStatePayload(payload) {
            return zoneState
        }
        if payload.count >= 8, payload[0] == 0x04 {
            return RGBPatch(r: Int(payload[5]), g: Int(payload[6]), b: Int(payload[7]))
        }
        if payload.count >= 4 {
            return RGBPatch(r: Int(payload[1]), g: Int(payload[2]), b: Int(payload[3]))
        }
        return nil
    }

    /// Stores Bluetooth button binding write data.
    struct BluetoothButtonBindingWrite {
        let device: MouseDevice
        let slot: UInt8
        let kind: ButtonBindingKind
        let hidKey: UInt8
        let hidModifiers: UInt8
        let turboEnabled: Bool
        let turboRate: UInt16
        let clutchDPI: Int?
    }

    func btSetButtonBinding(_ request: BluetoothButtonBindingWrite) async throws -> Bool {
        let payload = BLEVendorProtocol.buildButtonPayload(
            slot: request.slot,
            kind: request.kind,
            hidKey: request.hidKey,
            hidModifiers: request.hidModifiers,
            turboEnabled: request.turboEnabled,
            turboRate: request.turboRate,
            clutchDPI: request.clutchDPI
        )
        let req = nextBTReq()
        let header = BLEVendorProtocol.buildWriteHeader(req: req, payloadLength: 0x0A, key: .buttonBind(slot: request.slot))
        let notifies = try await btExchange([header, payload], timeout: 0.9, device: request.device)
        return btAckSuccess(notifies: notifies, req: req)
    }
}
