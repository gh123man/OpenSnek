import Foundation
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

/// Adds onboard profiles Bluetooth behavior to `BridgeClient`.
extension BridgeClient {
    func btReadPayload(device: MouseDevice, key: BLEVendorProtocol.Key, requestPayload: Data? = nil, timeout: TimeInterval = 0.6) async throws -> Data? {
        let req = nextBTReq()
        let writes: [Data]
        if let requestPayload { writes = BLEVendorProtocol.buildWriteFrames(req: req, key: key, payload: requestPayload) } else { writes = [BLEVendorProtocol.buildReadHeader(req: req, key: key)] }
        let notifies = try await btExchange(writes, timeout: timeout, device: device)
        let payload = BLEVendorProtocol.parsePayloadFrames(notifies: notifies, req: req)
        if payload == nil {
            AppLog.debug("Bridge", "btReadPayload no-payload device=\(device.id) key=\(btKeyLabel(key)) req=\(req) notifies=\(btNotifySummary(notifies))")
        } else if let payload, payload.isEmpty {
            AppLog.debug("Bridge", "btReadPayload empty-payload device=\(device.id) key=\(btKeyLabel(key)) req=\(req) notifies=\(btNotifySummary(notifies))")
        }
        return payload
    }

    func btWriteAck(device: MouseDevice, key: BLEVendorProtocol.Key, payload: Data = Data(), timeout: TimeInterval = 0.9) async throws -> Bool {
        let req = nextBTReq()
        let writes = BLEVendorProtocol.buildWriteFrames(req: req, key: key, payload: payload)
        let notifies = try await btExchange(writes, timeout: timeout, device: device)
        let ok = btAckSuccess(notifies: notifies, req: req)
        if !ok { AppLog.debug("Bridge", "btWriteAck rejected device=\(device.id) key=\(btKeyLabel(key)) req=\(req) payloadBytes=\(payload.count) notifies=\(btNotifySummary(notifies))") }
        return ok
    }

    func btListOnboardProfiles(device: MouseDevice, profile: DeviceProfile) async throws -> OnboardProfileInventory {
        let assigned = try await btReadOnboardProfileTargets(device: device, profile: profile)
        let active = try await btReadActiveOnboardProfileID(device: device) ?? 1
        let summaries = assigned.map { target in OnboardProfileSummary(profileID: target, metadata: nil, isAssigned: true, isActive: target == active, isBaseProfile: target == 1) }
        return OnboardProfileInventory(activeProfileID: active, maxProfileID: profile.onboardProfileCount, assignedProfileIDs: assigned, profiles: summaries)
    }

    func btReadOnboardProfileTargets(device: MouseDevice, profile: DeviceProfile) async throws -> [Int] {
        guard let targetPayload = try await btReadPayload(device: device, key: .profileTargetsGet()) else { throw BridgeError.commandFailed("Bluetooth onboard profile inventory read failed.") }
        return BLEVendorProtocol.parseProfileTargets(payload: targetPayload, maxProfileID: profile.onboardProfileCount)
    }

    func btReadActiveOnboardProfileID(device: MouseDevice) async throws -> Int? {
        guard let payload = try await btReadPayload(device: device, key: .profileActiveTargetGet()) else { return nil }
        return BLEVendorProtocol.parseActiveTarget(payload: payload)
    }

    func btReadOnboardProfile(device: MouseDevice, profile: DeviceProfile, target: Int, includeMetadata: Bool = true, includeButtonBindings: Bool = true) async throws -> OnboardProfileSnapshot {
        let metadata: OnboardProfileMetadata
        if !includeMetadata {
            metadata = OnboardProfileMetadata(name: target == 0 ? "Active Profile" : "Profile \(target)")
        } else if target == 0 {
            metadata = (try? await btReadOnboardProfileMetadata(device: device, target: target)) ?? OnboardProfileMetadata(name: "Active Profile")
        } else {
            metadata = try await btReadOnboardProfileMetadata(device: device, target: target)
        }
        let dpi = try await btReadOnboardProfileDPI(device: device, target: target)
        let bindings = includeButtonBindings ? try await btReadOnboardProfileButtons(device: device, profile: profile, target: target) : [:]
        let brightness = try await btReadOnboardProfileBrightness(device: device, target: target)
        let colors = try await btReadOnboardProfileStaticColors(device: device, target: target)
        return OnboardProfileSnapshot(profileID: target, metadata: metadata, dpi: dpi, buttonBindings: bindings, brightnessByLEDID: brightness, staticColorByLEDID: colors)
    }

    func btReadOnboardProfileMetadata(device: MouseDevice, target: Int, requireKnownFields: Bool = false) async throws -> OnboardProfileMetadata {
        let parsed = try await btReadOnboardProfileMetadataFields(device: device, target: target)
        if let metadata = Self.completeBluetoothOnboardProfileMetadata(parsed) { return metadata }
        if requireKnownFields { throw BridgeError.commandFailed("Bluetooth onboard profile metadata read did not include complete UUID/name/owner fields for target \(target).") }
        return OnboardProfileMetadata(identifier: parsed.identifier ?? UUID(), name: parsed.name ?? "Profile \(target)", owner: parsed.owner ?? OnboardProfileMetadata.synapseCompatibleFallbackOwner)
    }

    func btReadOnboardProfileMetadataFields(device: MouseDevice, target: Int) async throws -> USBHIDProtocol.OnboardProfileMetadata {
        var chunks: [BLEVendorProtocol.ProfileMetadataChunk] = []
        for offset in BLEVendorProtocol.onboardProfileMetadataChunkOffsets {
            let length = min(BLEVendorProtocol.onboardProfileMetadataChunkDataLength, BLEVendorProtocol.onboardProfileMetadataLength - offset)
            guard let payload = try await btReadPayload(device: device, key: .profileMetadataGet(target: UInt8(target)), requestPayload: BLEVendorProtocol.profileMetadataReadRequest(offset: offset, length: length)),
                let chunk = BLEVendorProtocol.profileMetadataChunk(from: payload, expectedOffset: offset)
            else { throw BridgeError.commandFailed("Bluetooth onboard profile metadata read failed at offset \(offset).") }
            chunks.append(chunk)
        }
        return BLEVendorProtocol.parseProfileMetadata(BLEVendorProtocol.mergeProfileMetadataChunks(chunks))
    }

    static func completeBluetoothOnboardProfileMetadata(_ parsed: USBHIDProtocol.OnboardProfileMetadata) -> OnboardProfileMetadata? {
        guard let identifier = parsed.identifier, let name = parsed.name, let owner = OnboardProfileMetadata.synapseCompatibleOwner(from: parsed.owner) else { return nil }
        return OnboardProfileMetadata(identifier: identifier, name: name, owner: owner)
    }

    func btMetadataForWrite(device: MouseDevice, profile: DeviceProfile, metadata: OnboardProfileMetadata, excludingProfileID: Int?) async -> OnboardProfileMetadata {
        let existingOwner = await btExistingSynapseOwnerHash(device: device, profile: profile, excludingProfileID: excludingProfileID)
        return metadata.withSynapseCompatibleOwner(Self.preferredProfileOwnerForWrite(preferred: metadata.owner, existing: existingOwner))
    }

    private func btExistingSynapseOwnerHash(device: MouseDevice, profile: DeviceProfile, excludingProfileID: Int?) async -> String? {
        guard let targets = try? await btReadOnboardProfileTargets(device: device, profile: profile) else { return nil }
        for target in targets where excludingProfileID.map({ target != $0 }) ?? true {
            guard let parsed = try? await btReadOnboardProfileMetadataFields(device: device, target: target), let owner = OnboardProfileMetadata.synapseCompatibleOwner(from: parsed.owner) else { continue }
            return owner
        }
        return nil
    }

    func btWriteOnboardProfileMetadata(device: MouseDevice, target: Int, metadata: OnboardProfileMetadata) async throws {
        let metadataForWrite = metadata.withSynapseCompatibleOwner()
        let bytes = BLEVendorProtocol.buildProfileMetadata(identifier: metadataForWrite.identifier, name: metadataForWrite.name, owner: metadataForWrite.owner)
        for offset in BLEVendorProtocol.onboardProfileMetadataChunkOffsets {
            let payload = BLEVendorProtocol.profileMetadataWritePayload(offset: offset, metadata: bytes)
            guard try await btWriteAck(device: device, key: .profileMetadataSet(target: UInt8(target)), payload: payload) else { throw BridgeError.commandFailed("Bluetooth onboard profile metadata write failed at offset \(offset).") }
        }
    }

    func btReadOnboardProfileDPI(device: MouseDevice, target: Int) async throws -> OnboardDPIProfileSnapshot? {
        let scalarPayload = try await btReadPayload(device: device, key: .dpiScalarGet(target: UInt8(target)))
        let scalar = scalarPayload.flatMap { BLEVendorProtocol.parseDpiScalarPair(blob: $0) }
        if let projection = try await btReadPayload(device: device, key: .dpiProjectionGet(target: UInt8(target))), let parsed = BLEVendorProtocol.parseDpiStageSnapshot(blob: projection) {
            return OnboardDPIProfileSnapshot(scalar: scalar, activeStage: parsed.active, pairs: Array(parsed.pairs.prefix(parsed.count)), stageIDs: parsed.stageIDs, marker: parsed.marker)
        }
        let pairPayload = try await btReadPayload(device: device, key: .dpiPairListGet(target: UInt8(target)))
        let pairs = pairPayload.flatMap { BLEVendorProtocol.parseDpiPairList(blob: $0) } ?? scalar.map { [$0] } ?? []
        let tokenPayload = try await btReadPayload(device: device, key: .dpiStageTokenGet(target: UInt8(target)))
        let token = tokenPayload?.first
        guard scalar != nil || !pairs.isEmpty else { return nil }
        let active = token.flatMap { raw in
            let ids = Array((0..<pairs.count).map { UInt8($0 + 1) })
            return BLEVendorProtocol.resolveActiveStage(activeRaw: Int(raw), stageIDs: ids, count: max(1, pairs.count))
        }
        return OnboardDPIProfileSnapshot(scalar: scalar, activeStage: active, pairs: pairs, stageIDs: Array((0..<pairs.count).map { UInt8($0 + 1) }), marker: 0x03)
    }

    func btReadOnboardProfileButtons(device: MouseDevice, profile: DeviceProfile, target: Int) async throws -> [Int: ButtonBindingDraft] {
        var bindings: [Int: ButtonBindingDraft] = [:]
        for slot in profile.buttonLayout.writableSlots {
            guard let payload = try await btReadPayload(device: device, key: .buttonBindGet(target: UInt8(target), slot: UInt8(slot))), let block = BLEVendorProtocol.extractBluetoothFunctionBlock(payload: payload, target: UInt8(target), slot: UInt8(slot), profileID: device.profile_id),
                let draft = ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(slot: slot, functionBlock: block, profileID: device.profile_id)
            else { continue }
            bindings[slot] = draft
        }
        return bindings
    }

    func btReadOnboardProfileBrightness(device: MouseDevice, target: Int) async throws -> [Int: Int] {
        var values: [Int: Int] = [:]
        for ledID in bluetoothLightingLEDIDs(device: device) {
            guard let value = try await btReadPayload(device: device, key: .profileLightingBrightnessGet(target: UInt8(target), ledID: ledID))?.first else { continue }
            values[Int(ledID)] = Int(value)
        }
        return values
    }

    func btReadOnboardProfileStaticColors(device: MouseDevice, target: Int) async throws -> [Int: RGBPatch] {
        var values: [Int: RGBPatch] = [:]
        for ledID in bluetoothLightingLEDIDs(device: device) {
            guard let payload = try await btReadPayload(device: device, key: .profileLightingZoneStateGet(target: UInt8(target), ledID: ledID)), let color = BLEVendorProtocol.parseV3ProLightingZoneStatePayload(payload) else { continue }
            values[Int(ledID)] = color
        }
        return values
    }

    func btCreateOnboardProfilePrelude(device: MouseDevice, target: Int) async throws {
        guard try await btWriteAck(device: device, key: .profileTargetDelete(target: UInt8(target)), payload: Data()) else { throw BridgeError.commandFailed("Bluetooth onboard profile create delete step failed.") }
        guard try await btWriteAck(device: device, key: .profileTargetPrepare(target: UInt8(target)), payload: Data([0x00])) else { throw BridgeError.commandFailed("Bluetooth onboard profile create prepare step failed.") }
        guard let statusPayload = try await btReadPayload(device: device, key: .profileTargetStatusGet(target: UInt8(target))), statusPayload.first == 0x01 else { throw BridgeError.commandFailed("Bluetooth onboard profile create status readback failed.") }
        guard try await btWriteAck(device: device, key: .profileTargetApply(target: UInt8(target)), payload: Data([0x00])) else { throw BridgeError.commandFailed("Bluetooth onboard profile create apply step failed.") }
        guard try await btWriteAck(device: device, key: .profileTargetCommit(target: UInt8(target)), payload: Data()) else { throw BridgeError.commandFailed("Bluetooth onboard profile create commit step failed.") }
    }

    func btApplyOnboardProfileMutation(device: MouseDevice, profile: DeviceProfile, target: Int, mutation: OnboardProfileMutation) async throws {
        if let dpi = mutation.dpi, !dpi.pairs.isEmpty { try await btWriteOnboardProfileDPI(device: device, target: target, dpi: dpi) }
        if let bindings = mutation.buttonBindings {
            for (slot, draft) in bindings where profile.buttonLayout.isEditable(slot) {
                let payload = BLEVendorProtocol.retargetButtonPayload(
                    BLEVendorProtocol.buildButtonPayload(
                        slot: UInt8(slot), kind: draft.kind, hidKey: UInt8(max(0, min(255, draft.hidKey))), hidModifiers: UInt8(max(0, min(255, draft.hidModifiers))), turboEnabled: draft.turboEnabled && draft.kind.supportsTurbo,
                        turboRate: UInt16(ButtonBindingSupport.clampTurboRate(draft.turboRate)), clutchDPI: draft.kind == .dpiClutch ? DeviceProfiles.clampDPI(draft.clutchDPI ?? ButtonBindingSupport.defaultBasiliskDPIClutchDPI, device: device) : nil), target: UInt8(target), slot: UInt8(slot))
                guard try await btWriteAck(device: device, key: .buttonBindSet(target: UInt8(target), slot: UInt8(slot)), payload: payload) else { throw BridgeError.commandFailed("Bluetooth onboard profile button write failed for slot \(slot).") }
            }
        }
        if let brightnessByLEDID = mutation.brightnessByLEDID, !brightnessByLEDID.isEmpty {
            guard try await btWriteAck(device: device, key: .profileTargetPrepare(target: UInt8(target)), payload: Data([0x00])) else { throw BridgeError.commandFailed("Bluetooth onboard profile brightness prepare failed.") }
            let brightness = brightnessByLEDID.values.max() ?? 0
            guard try await btWriteAck(device: device, key: .storedLightingBrightnessSet(target: UInt8(target)), payload: Data([UInt8(max(0, min(255, brightness)))])) else { throw BridgeError.commandFailed("Bluetooth onboard profile brightness write failed.") }
        }
        if let colors = mutation.staticColorByLEDID {
            for (ledID, color) in colors {
                let payload = BLEVendorProtocol.buildV3ProLightingZoneStatePayload(r: color.r, g: color.g, b: color.b)
                guard try await btWriteAck(device: device, key: .profileLightingZoneStateSet(target: UInt8(target), ledID: UInt8(ledID)), payload: payload) else { throw BridgeError.commandFailed("Bluetooth onboard profile static color write failed for LED \(ledID).") }
            }
        }
    }

    func btWriteOnboardProfileDPI(device: MouseDevice, target: Int, dpi: OnboardDPIProfileSnapshot) async throws {
        let count = DeviceProfiles.clampDpiStageCount(dpi.pairs.count)
        let active = max(0, min(count - 1, dpi.activeStage ?? 0))
        let pairs = Array(dpi.pairs.prefix(DeviceProfiles.maximumDpiStageCount))
        let payload = BLEVendorProtocol.buildDpiStagePayload(active: active, count: count, pairs: pairs, marker: dpi.marker ?? 0x03, stageIDs: dpi.stageIDs.isEmpty ? nil : dpi.stageIDs)
        guard try await btWriteAck(device: device, key: .storedDpiStagesSet(target: UInt8(target)), payload: payload) else { throw BridgeError.commandFailed("Bluetooth onboard profile DPI stage write failed.") }
        let scalar = dpi.scalar ?? pairs[active]
        let scalarPayload = Data([UInt8(scalar.x & 0xFF), UInt8((scalar.x >> 8) & 0xFF), UInt8(scalar.y & 0xFF), UInt8((scalar.y >> 8) & 0xFF), 0x00, 0x00])
        guard try await btWriteAck(device: device, key: .storedDpiScalarSet(target: UInt8(target)), payload: scalarPayload) else { throw BridgeError.commandFailed("Bluetooth onboard profile DPI scalar write failed.") }
    }

    func refreshActiveOnboardProfile(device: MouseDevice, profile: DeviceProfile) async throws -> MouseState {
        AppLog.warning("DPITrace", "bridge refreshActiveOnboardProfile start device=\(device.id) transport=\(device.transport.rawValue)")
        let rawActive: Int
        switch device.transport {
        case .usb:
            rawActive = try await withUSBProfileSession(device: device) { session in
                let active = try self.usbReadActiveOnboardProfileID(session, device) ?? 1
                try self.usbApplyCachedLogicalDPIToActiveLayerIfNeeded(session, device, profileID: active)
                return active
            }
        case .bluetooth: rawActive = try await btReadActiveOnboardProfileID(device: device) ?? 1
        }
        let active = max(1, min(profile.onboardProfileCount, rawActive))
        let state = storeProjectedActiveOnboardProfileState(device: device, profile: profile, activeProfileID: active)
        AppLog.warning("DPITrace", "bridge refreshActiveOnboardProfile end device=\(device.id) rawActive=\(rawActive) active=\(active) state={\(AppStateEditorController.diagnosticDPIState(state))}")
        return state
    }

    func storeProjectedActiveOnboardProfileState(device: MouseDevice, profile: DeviceProfile, activeProfileID: Int) -> MouseState {
        let previous = lastStateByDeviceID[device.id]
        let active = max(1, min(profile.onboardProfileCount, activeProfileID))
        if device.transport == .bluetooth {
            btDpiSnapshotByDeviceID.removeValue(forKey: device.id)
            btExpectedDpiByDeviceID.removeValue(forKey: device.id)
        }
        let state = MouseState(
            device: previous?.device ?? DeviceSummary(id: device.id, product_name: device.product_name, serial: device.serial, transport: device.transport, firmware: device.firmware), connection: previous?.connection ?? device.connectionLabel, battery_percent: previous?.battery_percent,
            charging: previous?.charging, dpi: nil, dpi_stages: DpiStages(active_stage: nil, values: nil), poll_rate: previous?.poll_rate, sleep_timeout: previous?.sleep_timeout, device_mode: previous?.device_mode, low_battery_threshold_raw: previous?.low_battery_threshold_raw,
            scroll_mode: previous?.scroll_mode, scroll_acceleration: previous?.scroll_acceleration, scroll_smart_reel: previous?.scroll_smart_reel, active_onboard_profile: active, onboard_profile_count: profile.onboardProfileCount, led_value: previous?.led_value,
            capabilities: previous?.capabilities ?? Capabilities(dpi_stages: true, poll_rate: device.transport == .usb, power_management: true, button_remap: true, lighting: device.showsLightingControls))
        lastStateByDeviceID[device.id] = state
        return state
    }

    func storeProjectedActiveOnboardProfileState(device: MouseDevice, profile: DeviceProfile, activeProfileID: Int, snapshot: OnboardProfileSnapshot) -> MouseState {
        let previous = lastStateByDeviceID[device.id]
        let active = max(1, min(profile.onboardProfileCount, activeProfileID))
        let state = stateFromActiveOnboardProfileSnapshot(device: device, profile: profile, activeProfileID: active, snapshot: snapshot, previous: previous)
        seedBluetoothOnboardProfileDpiSnapshotIfNeeded(device: device, snapshot: snapshot)
        lastStateByDeviceID[device.id] = state
        return state
    }

    nonisolated static func bluetoothDpiSnapshot(from dpi: OnboardDPIProfileSnapshot) -> BLEVendorProtocol.DpiStageSnapshot {
        let count = DeviceProfiles.clampDpiStageCount(dpi.pairs.isEmpty ? 1 : dpi.pairs.count)
        var pairs = Array(dpi.pairs.prefix(DeviceProfiles.maximumDpiStageCount))
        if pairs.isEmpty { pairs = [dpi.scalar ?? DpiPair(x: 800, y: 800)] }
        while pairs.count < DeviceProfiles.maximumDpiStageCount { pairs.append(pairs.last ?? DpiPair(x: 800, y: 800)) }
        var stageIDs = Array(dpi.stageIDs.prefix(DeviceProfiles.maximumDpiStageCount))
        if stageIDs.isEmpty { stageIDs = Array((1...DeviceProfiles.maximumDpiStageCount).map(UInt8.init)) }
        while stageIDs.count < DeviceProfiles.maximumDpiStageCount { stageIDs.append(stageIDs.last.map { $0 &+ 1 } ?? UInt8(stageIDs.count + 1)) }
        let active = max(0, min(count - 1, dpi.activeStage ?? 0))
        return BLEVendorProtocol.DpiStageSnapshot(active: active, count: count, slots: pairs.map(\.x), pairs: pairs, stageIDs: stageIDs, marker: dpi.marker ?? 0x03)
    }

    private func seedBluetoothOnboardProfileDpiSnapshotIfNeeded(device: MouseDevice, snapshot: OnboardProfileSnapshot) {
        guard device.transport == .bluetooth, let dpi = snapshot.dpi else { return }
        btDpiSnapshotByDeviceID[device.id] = Self.bluetoothDpiSnapshot(from: dpi)
        btExpectedDpiByDeviceID.removeValue(forKey: device.id)
    }

    func stateFromActiveOnboardProfileSnapshot(device: MouseDevice, profile: DeviceProfile, activeProfileID: Int, snapshot: OnboardProfileSnapshot, previous: MouseState?) -> MouseState {
        let activeStage = snapshot.dpi?.activeStage ?? previous?.dpi_stages.active_stage
        let pairs = snapshot.dpi?.pairs
        let values = pairs?.map(\.x) ?? previous?.dpi_stages.values
        let activePair: DpiPair? = {
            if let pairs, let activeStage, pairs.indices.contains(activeStage) { return pairs[activeStage] }
            return snapshot.dpi?.scalar ?? previous?.dpi
        }()
        return MouseState(
            device: previous?.device ?? DeviceSummary(id: device.id, product_name: device.product_name, serial: device.serial, transport: device.transport, firmware: device.firmware), connection: previous?.connection ?? device.connectionLabel, battery_percent: previous?.battery_percent,
            charging: previous?.charging, dpi: activePair, dpi_stages: DpiStages(active_stage: activeStage, values: values, pairs: pairs ?? previous?.dpi_stages.pairs), poll_rate: previous?.poll_rate, sleep_timeout: previous?.sleep_timeout, device_mode: previous?.device_mode,
            low_battery_threshold_raw: previous?.low_battery_threshold_raw, scroll_mode: snapshot.scrollMode ?? previous?.scroll_mode, scroll_acceleration: snapshot.scrollAcceleration ?? previous?.scroll_acceleration, scroll_smart_reel: snapshot.scrollSmartReel ?? previous?.scroll_smart_reel,
            active_onboard_profile: activeProfileID, onboard_profile_count: profile.onboardProfileCount, led_value: snapshot.brightnessByLEDID.values.max() ?? previous?.led_value,
            capabilities: previous?.capabilities ?? Capabilities(dpi_stages: true, poll_rate: device.transport == .usb, power_management: true, button_remap: true, lighting: device.showsLightingControls))
    }
}
