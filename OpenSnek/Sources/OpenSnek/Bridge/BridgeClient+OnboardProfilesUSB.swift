import Foundation
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

struct USBOnboardProfileMetadataRead {
    let parsed: USBHIDProtocol.OnboardProfileMetadata
    let metadata: OnboardProfileMetadata?
}

extension BridgeClient {
    func mappedOnboardProfileSupport(for device: MouseDevice) throws -> DeviceProfile {
        guard let profile = DeviceProfiles.resolve(
            vendorID: device.vendor_id,
            productID: device.product_id,
            transport: device.transport
        ), profile.supportsMappedOnboardProfileCRUD else {
            throw BridgeError.commandFailed("Mapped onboard profile CRUD is not supported on this device.")
        }
        return profile
    }

    func resolveCreateTarget(
        requested: Int?,
        inventory: OnboardProfileInventory,
        replaceAssignedProfile: Bool
    ) throws -> Int {
        if let requested {
            guard requested >= 2, requested <= inventory.maxProfileID else {
                throw BridgeError.commandFailed("Onboard profile \(requested) is outside the assignable profile range.")
            }
            if inventory.assignedProfileIDs.contains(requested), !replaceAssignedProfile {
                throw BridgeError.commandFailed("Onboard profile \(requested) is already assigned.")
            }
            return requested
        }
        guard let first = inventory.assignableProfileIDs.first else {
            throw BridgeError.commandFailed("No unassigned onboard profile slots are available.")
        }
        return first
    }

    func withUSBProfileSession<T>(
        device: MouseDevice,
        operation: (USBHIDControlSession) throws -> T
    ) async throws -> T {
        guard device.transport == .usb else {
            throw BridgeError.commandFailed("USB onboard profile operation requested for non-USB device.")
        }
        try await deferUSBReconnectReadIfNeeded(deviceID: device.id, operation: "onboard-profile")
        let sessions = sessionsFor(device: device)
        guard !sessions.isEmpty else {
            throw BridgeError.commandFailed("Device not available")
        }

        let session = sessions[0]
        do {
            let value = try session.withExclusiveDeviceAccess {
                try operation(session)
            }
            deviceSessions[device.id] = session
            return value
        } catch {
            throw error
        }
    }

    func validateUSBOnboardProfileReadback<T>(
        device: MouseDevice,
        operation: String,
        failureMessage: String,
        read: () throws -> T,
        accepts: (T) -> Bool
    ) throws -> T {
        let value: T
        do {
            value = try read()
        } catch {
            AppLog.error(
                "Bridge",
                "\(operation) readback failed device=\(device.id): \(error.localizedDescription)"
            )
            throw error
        }
        guard accepts(value) else {
            AppLog.error(
                "Bridge",
                "\(operation) readback validation failed device=\(device.id)"
            )
            throw BridgeError.commandFailed(failureMessage)
        }
        return value
    }

    func validateOnboardProfileReadback<T>(
        device: MouseDevice,
        operation: String,
        failureMessage: String,
        read: () async throws -> T,
        accepts: (T) -> Bool
    ) async throws -> T {
        let value: T
        do {
            value = try await read()
        } catch {
            AppLog.error(
                "Bridge",
                "\(operation) readback failed device=\(device.id): \(error.localizedDescription)"
            )
            throw error
        }
        guard accepts(value) else {
            AppLog.error(
                "Bridge",
                "\(operation) readback validation failed device=\(device.id)"
            )
            throw BridgeError.commandFailed(failureMessage)
        }
        return value
    }

    func usbListOnboardProfiles(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profile: DeviceProfile
    ) throws -> OnboardProfileInventory {
        let parsed = try usbReadOnboardProfileInventory(session, device, profile: profile)
        let active = try usbReadActiveOnboardProfileID(session, device) ?? 1
        let maxProfileID = max(Int(parsed.maxProfileID), profile.onboardProfileCount)
        let assigned = Set(parsed.assignedProfiles.map(Int.init))
        let summaries = assigned.sorted().map { profileID in
            let metadata = try? usbReadOnboardProfileMetadata(session, device, profileID: profileID)
            return OnboardProfileSummary(
                profileID: profileID,
                metadata: metadata,
                isAssigned: true,
                isActive: profileID == active,
                isBaseProfile: profileID == 1
            )
        }
        return OnboardProfileInventory(
            activeProfileID: active,
            maxProfileID: maxProfileID,
            assignedProfileIDs: Array(assigned).sorted(),
            profiles: summaries
        )
    }

    func usbReadOnboardProfileInventory(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profile _: DeviceProfile
    ) throws -> USBHIDProtocol.OnboardProfileInventory {
        guard let inventoryResponse = try perform(session, device, classID: 0x05, cmdID: 0x81, size: 0x00),
              let parsed = USBHIDProtocol.onboardProfileInventory(from: inventoryResponse) else {
            throw BridgeError.commandFailed("USB onboard profile inventory read failed.")
        }
        return parsed
    }

    func usbReadActiveOnboardProfileID(_ session: USBHIDControlSession, _ device: MouseDevice) throws -> Int? {
        guard let response = try perform(session, device, classID: 0x05, cmdID: 0x84, size: 0x00),
              let active = USBHIDProtocol.activeProfileID(from: response) else {
            return nil
        }
        return Int(active)
    }

    func usbWriteActiveOnboardProfileID(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profileID: Int
    ) throws -> Int {
        let response = try perform(
            session,
            device,
            classID: 0x05,
            cmdID: 0x04,
            size: 0x01,
            args: USBHIDProtocol.activeProfileSetArgs(profile: UInt8(profileID))
        )
        guard let response,
              USBHIDProtocol.activeProfileSetAccepted(from: response, profile: UInt8(profileID)) else {
            throw BridgeError.commandFailed("USB onboard profile selector was rejected.")
        }
        return try validateUSBOnboardProfileReadback(
            device: device,
            operation: "USB active onboard profile selector",
            failureMessage: "USB active profile readback did not match profile \(profileID).",
            read: {
                try self.usbReadActiveOnboardProfileID(session, device) ?? -1
            },
            accepts: { active in
                active == profileID
            }
        )
    }

    func usbReadOnboardProfile(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profile: DeviceProfile,
        profileID: Int,
        includeMetadata: Bool = true,
        includeButtonBindings: Bool = true
    ) throws -> OnboardProfileSnapshot {
        let metadata: OnboardProfileMetadata
        if !includeMetadata {
            metadata = OnboardProfileMetadata(name: profileID == 0 ? "Active Profile" : "Profile \(profileID)")
        } else if profileID == 0 {
            metadata = (try? usbReadOnboardProfileMetadata(session, device, profileID: profileID))
                ?? OnboardProfileMetadata(name: "Active Profile")
        } else {
            metadata = try usbReadOnboardProfileMetadata(session, device, profileID: profileID)
        }
        let dpi = try usbReadOnboardProfileDPI(session, device, profileID: profileID)
        let bindings = includeButtonBindings
            ? try usbReadOnboardProfileButtons(session, device, profile: profile, profileID: profileID)
            : [:]
        let brightness = try usbReadOnboardProfileBrightness(session, device, profileID: profileID)
        let colors = try usbReadOnboardProfileStaticColors(session, device, profileID: profileID)
        let scrollProfileID: Int
        if profileID == 0 {
            scrollProfileID = (try? usbReadActiveOnboardProfileID(session, device)) ?? 1
        } else {
            scrollProfileID = profileID
        }
        let scrollMode = try getScrollMode(session, device, profileID: scrollProfileID)
        let scrollAcceleration = try getScrollAcceleration(session, device, profileID: scrollProfileID)
        let scrollSmartReel = try getScrollSmartReel(session, device, profileID: scrollProfileID)
        return OnboardProfileSnapshot(
            profileID: profileID,
            metadata: metadata,
            dpi: dpi,
            buttonBindings: bindings,
            brightnessByLEDID: brightness,
            staticColorByLEDID: colors,
            scrollMode: scrollMode,
            scrollAcceleration: scrollAcceleration,
            scrollSmartReel: scrollSmartReel
        )
    }

    func usbReadOnboardProfileMetadataCandidate(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profileID: Int,
        requireKnownFields: Bool = false
    ) throws -> USBOnboardProfileMetadataRead {
        let slot = UInt8(max(0, min(255, profileID)))
        var chunks: [USBHIDProtocol.OnboardProfileMetadataChunk] = []
        for offset in USBHIDProtocol.onboardProfileMetadataChunkOffsets {
            guard let response = try perform(
                session,
                device,
                classID: 0x05,
                cmdID: 0x88,
                size: USBHIDProtocol.onboardProfileMetadataReadSize,
                args: USBHIDProtocol.onboardProfileMetadataReadArgs(slot: slot, offset: offset)
            ) else {
                continue
            }
            guard let chunk = USBHIDProtocol.onboardProfileMetadataChunk(
                from: response,
                expectedSlot: slot,
                expectedOffset: offset
            ) else {
                continue
            }
            chunks.append(chunk)
        }

        if requireKnownFields {
            let presentOffsets = Set(chunks.map(\.offset))
            let missingOffsets = USBHIDProtocol.onboardProfileMetadataWritableChunkOffsets
                .filter { !presentOffsets.contains($0) }
            if !missingOffsets.isEmpty {
                let missingDescription = missingOffsets.map(String.init).joined(separator: ",")
                throw BridgeError.commandFailed(
                    "USB onboard profile metadata read incomplete for profile \(profileID); " +
                    "missing offsets \(missingDescription)."
                )
            }
        }

        let parsed = USBHIDProtocol.parseOnboardProfileMetadata(
            USBHIDProtocol.mergeOnboardProfileMetadataChunks(chunks)
        )
        let metadata: OnboardProfileMetadata?
        if let identifier = parsed.identifier,
           let name = parsed.name,
           let owner = OnboardProfileMetadata.synapseCompatibleOwner(from: parsed.owner) {
            metadata = OnboardProfileMetadata(
                identifier: identifier,
                name: name,
                owner: owner
            )
        } else {
            metadata = nil
        }
        return USBOnboardProfileMetadataRead(parsed: parsed, metadata: metadata)
    }

    func usbMetadataForWrite(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        metadata: OnboardProfileMetadata,
        excludingProfileID: Int?
    ) -> OnboardProfileMetadata {
        metadata.withSynapseCompatibleOwner(
            Self.preferredProfileOwnerForWrite(
                preferred: metadata.owner,
                existing: usbExistingSynapseOwnerHash(
                    session,
                    device,
                    excludingProfileID: excludingProfileID
                )
            )
        )
    }

    private func usbExistingSynapseOwnerHash(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        excludingProfileID: Int?
    ) -> String? {
        guard let response = try? perform(
            session,
            device,
            classID: 0x05,
            cmdID: 0x81,
            size: 0x00
        ), let inventory = USBHIDProtocol.onboardProfileInventory(from: response) else {
            return nil
        }

        for profileID in inventory.assignedProfiles.map(Int.init).sorted()
            where excludingProfileID.map({ profileID != $0 }) ?? true {
            guard let read = try? usbReadOnboardProfileMetadataCandidate(
                session,
                device,
                profileID: profileID,
                requireKnownFields: false
            ), let owner = OnboardProfileMetadata.synapseCompatibleOwner(from: read.parsed.owner) else {
                continue
            }
            return owner
        }
        return nil
    }

    static func preferredProfileOwnerForWrite(preferred: String, existing: String?) -> String {
        let fallback = OnboardProfileMetadata.synapseCompatibleFallbackOwner
        let preferredOwner = OnboardProfileMetadata.synapseCompatibleOwner(from: preferred)
        if let preferredOwner, preferredOwner != fallback {
            return preferredOwner
        }
        if let existingOwner = OnboardProfileMetadata.synapseCompatibleOwner(from: existing) {
            return existingOwner
        }
        return preferredOwner ?? fallback
    }

    func usbReadOnboardProfileMetadata(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profileID: Int,
        requireKnownFields: Bool = false
    ) throws -> OnboardProfileMetadata {
        let read = try usbReadOnboardProfileMetadataCandidate(
            session,
            device,
            profileID: profileID,
            requireKnownFields: requireKnownFields
        )
        if requireKnownFields, read.metadata == nil {
            throw BridgeError.commandFailed("USB onboard profile metadata read did not include complete UUID/name/owner fields for profile \(profileID).")
        }
        return read.metadata ?? OnboardProfileMetadata(
            identifier: read.parsed.identifier ?? UUID(),
            name: read.parsed.name ?? "Profile \(profileID)",
            owner: read.parsed.owner ?? OnboardProfileMetadata.synapseCompatibleFallbackOwner
        )
    }

    func usbWriteOnboardProfileMetadata(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profileID: Int,
        metadata: OnboardProfileMetadata,
        mode: String = "write"
    ) throws {
        let metadataForWrite = metadata.withSynapseCompatibleOwner()
        let bytes = USBHIDProtocol.buildOnboardProfileMetadata(
            identifier: metadataForWrite.identifier,
            name: metadataForWrite.name,
            owner: metadataForWrite.owner
        )
        for offset in USBHIDProtocol.onboardProfileMetadataWritableChunkOffsets {
            let isTailOffset = offset >= USBHIDProtocol.onboardProfileMetadataKnownFieldLength
            AppLog.debug(
                "Bridge",
                "USB onboard profile metadata write start device=\(device.id) profile=\(profileID) " +
                "offset=\(offset) mode=\(mode) name=\"\(metadata.name)\" uuid=\(metadata.identifier.uuidString)"
            )
            let response = try perform(
                session,
                device,
                classID: 0x05,
                cmdID: 0x08,
                size: USBHIDProtocol.onboardProfileMetadataReadSize,
                args: USBHIDProtocol.onboardProfileMetadataWriteArgs(
                    slot: UInt8(profileID),
                    offset: offset,
                    metadata: bytes
                ),
                responseAttempts: isTailOffset ? 16 : 10,
                responseDelayUs: 50_000
            )
            guard response?[0] == 0x02 else {
                let lastStatus = response.map { String(format: "0x%02X", $0[0]) } ?? "nil"
                let failure = BridgeError.commandFailed(
                    "USB onboard profile metadata write failed at offset \(offset) (status \(lastStatus))."
                )
                if isTailOffset {
                    AppLog.warning(
                        "Bridge",
                        "USB onboard profile metadata tail response indeterminate device=\(device.id) " +
                        "profile=\(profileID) offset=\(offset) status=\(lastStatus); verifying strict readback"
                    )
                    if let readback = try? validateUSBOnboardProfileReadback(
                        device: device,
                        operation: "USB onboard profile metadata tail",
                        failureMessage: "USB onboard profile metadata tail readback did not match profile \(profileID).",
                        read: {
                            try self.usbReadOnboardProfileMetadata(
                                session,
                                device,
                                profileID: profileID,
                                requireKnownFields: true
                            )
                        },
                        accepts: { readback in
                            readback.identifier == metadataForWrite.identifier &&
                                readback.name == metadataForWrite.name &&
                                readback.owner == metadataForWrite.owner
                        }
                    ) {
                        AppLog.warning(
                            "Bridge",
                            "USB onboard profile metadata accepted after tail readback " +
                            "device=\(device.id) profile=\(profileID) name=\"\(readback.name)\""
                        )
                        return
                    }
                }
                throw failure
            }
            AppLog.debug(
                "Bridge",
                "USB onboard profile metadata write ok device=\(device.id) profile=\(profileID) " +
                "offset=\(offset) mode=\(mode)"
            )
            usleep(25_000)
        }
    }

    func usbReadOnboardProfileDPI(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profileID: Int
    ) throws -> OnboardDPIProfileSnapshot? {
        let storage = UInt8(max(0, min(255, profileID)))
        let scalar: DpiPair? = {
            guard let response = try? perform(
                session,
                device,
                classID: 0x04,
                cmdID: 0x85,
                size: 0x07,
                args: [storage, 0, 0, 0, 0, 0, 0]
            ), response[0] == 0x02 else {
                return nil
            }
            return DpiPair(
                x: (Int(response[9]) << 8) | Int(response[10]),
                y: (Int(response[11]) << 8) | Int(response[12])
            )
        }()
        let stages = try usbReadOnboardProfileDPIStages(session, device, profileID: profileID)
        guard scalar != nil || stages != nil else { return nil }
        return OnboardDPIProfileSnapshot(
            scalar: scalar,
            activeStage: stages?.active,
            pairs: stages?.pairs ?? scalar.map { [$0] } ?? [],
            stageIDs: stages?.stageIDs ?? [],
            marker: nil
        )
    }

    func usbReadOnboardProfileDPIStages(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profileID: Int
    ) throws -> USBDpiStageSnapshot? {
        guard let response = try perform(
            session,
            device,
            classID: 0x04,
            cmdID: 0x86,
            size: 0x26,
            args: [UInt8(profileID)]
        ), let snapshot = parseUSBDpiStageSnapshotResponse(response, device: device) else {
            return nil
        }
        return snapshot
    }

    func usbReadOnboardProfileButtons(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profile: DeviceProfile,
        profileID: Int
    ) throws -> [Int: ButtonBindingDraft] {
        var bindings: [Int: ButtonBindingDraft] = [:]
        for slot in profile.buttonLayout.writableSlots {
            guard let block = try getButtonBindingUSBRaw(
                session,
                device,
                profile: UInt8(profileID),
                slot: UInt8(slot),
                hypershift: 0x00
            ), let draft = ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(
                slot: slot,
                functionBlock: block,
                profileID: device.profile_id
            ) else {
                continue
            }
            bindings[slot] = draft
        }
        return bindings
    }

    func usbReadOnboardProfileBrightness(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profileID: Int
    ) throws -> [Int: Int] {
        var values: [Int: Int] = [:]
        for ledID in usbLightingLEDIDs(for: device) {
            guard let response = try perform(
                session,
                device,
                classID: 0x0F,
                cmdID: 0x84,
                size: 0x03,
                args: [UInt8(profileID), ledID, 0x00]
            ), response[0] == 0x02 else {
                continue
            }
            values[Int(ledID)] = Int(response[10])
        }
        return values
    }

    func usbReadOnboardProfileStaticColors(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profileID: Int
    ) throws -> [Int: RGBPatch] {
        var values: [Int: RGBPatch] = [:]
        for ledID in usbLightingLEDIDs(for: device) {
            guard let response = try perform(
                session,
                device,
                classID: 0x0F,
                cmdID: 0x82,
                size: 0x0C,
                args: USBHIDProtocol.profileLightingEffectReadArgs(
                    profile: UInt8(profileID),
                    ledID: ledID
                )
            ), let state = USBHIDProtocol.profileLightingEffectState(
                from: response,
                expectedLEDID: ledID
            ), let color = state.staticColor else {
                continue
            }
            values[Int(ledID)] = color
        }
        return values
    }

    func usbApplyOnboardProfileMutation(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profile: DeviceProfile,
        profileID: Int,
        mutation: OnboardProfileMutation
    ) throws {
        if let dpi = mutation.dpi, !dpi.pairs.isEmpty {
            try usbWriteOnboardProfileDPIStages(session, device, profileID: profileID, dpi: dpi)
            if let scalar = dpi.scalar ?? dpi.activeStage.flatMap({ active in
                dpi.pairs.indices.contains(active) ? dpi.pairs[active] : nil
            }) {
                try usbWriteOnboardProfileDPIScalar(session, device, profileID: profileID, pair: scalar)
            }
        }
        if let bindings = mutation.buttonBindings {
            for (slot, draft) in bindings where profile.buttonLayout.isEditable(slot) {
                let block = ButtonBindingSupport.buildUSBFunctionBlock(
                    slot: slot,
                    kind: draft.kind,
                    hidKey: draft.hidKey,
                    hidModifiers: draft.hidModifiers,
                    turboEnabled: draft.turboEnabled && draft.kind.supportsTurbo,
                    turboRate: draft.turboRate,
                    clutchDPI: draft.clutchDPI,
                    profileID: device.profile_id
                )
                guard try setButtonBindingUSBRaw(
                    session,
                    device,
                    request: USBRawButtonBindingWrite(
                        profile: UInt8(profileID),
                        slot: UInt8(slot),
                        hypershift: 0x00,
                        functionBlock: block
                    )
                ) else {
                    throw BridgeError.commandFailed("USB onboard profile button write failed for slot \(slot).")
                }
            }
        }
        if let brightnessByLEDID = mutation.brightnessByLEDID {
            for (ledID, brightness) in brightnessByLEDID {
                guard let response = try perform(
                    session,
                    device,
                    classID: 0x0F,
                    cmdID: 0x04,
                    size: 0x03,
                    args: [UInt8(profileID), UInt8(ledID), UInt8(max(0, min(255, brightness)))]
                ), response[0] == 0x02 else {
                    throw BridgeError.commandFailed("USB onboard profile brightness write failed for LED \(ledID).")
                }
            }
        }
        if let colors = mutation.staticColorByLEDID {
            for (ledID, color) in colors {
                let args = USBHIDProtocol.profileLightingStaticColorSetArgs(
                    profile: UInt8(profileID),
                    ledID: UInt8(ledID),
                    color: color
                )
                guard let response = try perform(
                    session,
                    device,
                    classID: 0x0F,
                    cmdID: 0x02,
                    size: UInt8(args.count),
                    args: args
                ), response[0] == 0x02 else {
                    throw BridgeError.commandFailed("USB onboard profile static color write failed for LED \(ledID).")
                }
            }
        }
        if let scrollMode = mutation.scrollMode,
           !(try setScrollMode(session, device, mode: scrollMode, profileID: profileID)) {
            throw BridgeError.commandFailed("USB onboard profile scroll mode write failed.")
        }
        if let scrollAcceleration = mutation.scrollAcceleration,
           !(try setScrollAcceleration(session, device, enabled: scrollAcceleration, profileID: profileID)) {
            throw BridgeError.commandFailed("USB onboard profile scroll acceleration write failed.")
        }
        if let scrollSmartReel = mutation.scrollSmartReel,
           !(try setScrollSmartReel(session, device, enabled: scrollSmartReel, profileID: profileID)) {
            throw BridgeError.commandFailed("USB onboard profile smart reel write failed.")
        }
    }

    func usbWriteOnboardProfileDPIScalar(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profileID: Int,
        pair: DpiPair
    ) throws {
        let x = DeviceProfiles.clampDPI(pair.x, device: device)
        let y = DeviceProfiles.clampDPI(pair.y, device: device)
        let args: [UInt8] = [
            UInt8(profileID),
            UInt8((x >> 8) & 0xFF),
            UInt8(x & 0xFF),
            UInt8((y >> 8) & 0xFF),
            UInt8(y & 0xFF),
            0x00,
            0x00
        ]
        guard let response = try perform(session, device, classID: 0x04, cmdID: 0x05, size: 0x07, args: args),
              response[0] == 0x02 else {
            throw BridgeError.commandFailed("USB onboard profile DPI scalar write failed.")
        }
    }

    func usbWriteOnboardProfileDPIStages(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profileID: Int,
        dpi: OnboardDPIProfileSnapshot
    ) throws {
        let count = DeviceProfiles.clampDpiStageCount(dpi.pairs.count)
        let active = max(0, min(count - 1, dpi.activeStage ?? 0))
        let stageIDs = usbStageIDsForWrite(count: count, stageIDs: dpi.stageIDs)
        var args = [UInt8](repeating: 0, count: 3 + count * 7)
        args[0] = UInt8(profileID)
        args[1] = stageIDs[active]
        args[2] = UInt8(count)
        var offset = 3
        for index in 0..<count {
            let pair = dpi.pairs[index]
            let x = DeviceProfiles.clampDPI(pair.x, device: device)
            let y = DeviceProfiles.clampDPI(pair.y, device: device)
            args[offset] = stageIDs[index]
            args[offset + 1] = UInt8((x >> 8) & 0xFF)
            args[offset + 2] = UInt8(x & 0xFF)
            args[offset + 3] = UInt8((y >> 8) & 0xFF)
            args[offset + 4] = UInt8(y & 0xFF)
            offset += 7
        }
        guard let response = try perform(session, device, classID: 0x04, cmdID: 0x06, size: 0x26, args: args),
              response[0] == 0x02 else {
            throw BridgeError.commandFailed("USB onboard profile DPI stage write failed.")
        }
    }

}
