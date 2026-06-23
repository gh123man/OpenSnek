import Foundation
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

extension BridgeClient {
    func listOnboardProfiles(device: MouseDevice) async throws -> OnboardProfileInventory {
        let profile = try mappedOnboardProfileSupport(for: device)
        switch device.transport {
        case .usb:
            return try await withUSBProfileSession(device: device) { session in
                try self.usbListOnboardProfiles(session, device, profile: profile)
            }
        case .bluetooth:
            return try await btListOnboardProfiles(device: device, profile: profile)
        }
    }

    func readOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot {
        let profile = try mappedOnboardProfileSupport(for: device)
        let clampedProfileID = max(0, min(profile.onboardProfileCount, profileID))
        switch device.transport {
        case .usb:
            return try await withUSBProfileSession(device: device) { session in
                try self.usbReadOnboardProfile(
                    session,
                    device,
                    profile: profile,
                    profileID: clampedProfileID,
                    includeButtonBindings: true
                )
            }
        case .bluetooth:
            return try await btReadOnboardProfile(
                device: device,
                profile: profile,
                target: clampedProfileID,
                includeButtonBindings: true
            )
        }
    }

    func readOnboardProfileCore(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot {
        let profile = try mappedOnboardProfileSupport(for: device)
        let clampedProfileID = max(0, min(profile.onboardProfileCount, profileID))
        switch device.transport {
        case .usb:
            return try await withUSBProfileSession(device: device) { session in
                try self.usbReadOnboardProfile(
                    session,
                    device,
                    profile: profile,
                    profileID: clampedProfileID,
                    includeMetadata: false,
                    includeButtonBindings: false
                )
            }
        case .bluetooth:
            return try await btReadOnboardProfile(
                device: device,
                profile: profile,
                target: clampedProfileID,
                includeMetadata: false,
                includeButtonBindings: false
            )
        }
    }

    func readOnboardProfileButtonBindings(device: MouseDevice, profileID: Int) async throws -> [Int: ButtonBindingDraft] {
        let profile = try mappedOnboardProfileSupport(for: device)
        let clampedProfileID = max(0, min(profile.onboardProfileCount, profileID))
        switch device.transport {
        case .usb:
            return try await withUSBProfileSession(device: device) { session in
                try self.usbReadOnboardProfileButtons(
                    session,
                    device,
                    profile: profile,
                    profileID: clampedProfileID
                )
            }
        case .bluetooth:
            return try await btReadOnboardProfileButtons(
                device: device,
                profile: profile,
                target: clampedProfileID
            )
        }
    }

    func createOnboardProfile(
        device: MouseDevice,
        mutation: OnboardProfileMutation,
        targetProfileID: Int?,
        replaceAssignedProfile: Bool
    ) async throws -> OnboardProfileSnapshot {
        let profile = try mappedOnboardProfileSupport(for: device)
        let target = try await resolveCreateTargetForOnboardCreate(
            device: device,
            profile: profile,
            requested: targetProfileID,
            replaceAssignedProfile: replaceAssignedProfile
        )
        var createMutation = mutation
        if createMutation.metadata == nil {
            createMutation.metadata = OnboardProfileMetadata(name: "Profile \(target)")
        }
        if createMutation.needsMappedContentFill(for: device) {
            let activeSnapshot = try? await readOnboardProfile(device: device, profileID: 0)
            createMutation = createMutation.fillingMissingMappedContent(from: activeSnapshot)
        }
        var createdMetadata = createMutation.metadata!
        switch device.transport {
        case .usb:
            return try await withUSBProfileSession(device: device) { session in
                createdMetadata = self.usbMetadataForWrite(
                    session,
                    device,
                    metadata: createdMetadata,
                    excludingProfileID: target
                )
                createMutation.metadata = createdMetadata
                let response = try self.perform(
                    session,
                    device,
                    classID: 0x05,
                    cmdID: 0x02,
                    size: 0x01,
                    args: USBHIDProtocol.onboardProfileCreateArgs(profile: UInt8(target))
                )
                guard let response,
                      USBHIDProtocol.onboardProfileCreateAccepted(from: response, profile: UInt8(target)) else {
                    throw BridgeError.commandFailed("USB onboard profile create was rejected.")
                }
                try self.usbWriteOnboardProfileMetadata(
                    session,
                    device,
                    profileID: target,
                    metadata: createdMetadata
                )
                let dpiWriteContext = try? self.usbReadOnboardProfileDPI(
                    session,
                    device,
                    profileID: target
                )
                try self.usbApplyOnboardProfileMutation(
                    session,
                    device,
                    profile: profile,
                    profileID: target,
                    mutation: createMutation.withoutMetadata,
                    dpiWriteContext: dpiWriteContext
                )
                _ = try self.validateUSBOnboardProfileReadback(
                    device: device,
                    operation: "USB onboard profile create inventory",
                    failureMessage: "USB onboard profile create readback did not list profile \(target).",
                    read: {
                        try self.usbListOnboardProfiles(session, device, profile: profile)
                    },
                    accepts: { inventory in
                        inventory.assignedProfileIDs.contains(target)
                    }
                )
                return try self.validateUSBOnboardProfileReadback(
                    device: device,
                    operation: "USB onboard profile create snapshot",
                    failureMessage: "USB onboard profile create snapshot readback failed for profile \(target).",
                    read: {
                        try self.usbReadOnboardProfile(session, device, profile: profile, profileID: target)
                    },
                    accepts: { snapshot in
                        snapshot.profileID == target && snapshot.metadata.name == createdMetadata.name
                    }
                )
            }
        case .bluetooth:
            createdMetadata = await btMetadataForWrite(
                device: device,
                profile: profile,
                metadata: createdMetadata,
                excludingProfileID: target
            )
            createMutation.metadata = createdMetadata
            let projectedCreate = createMutation.projectedSnapshot(profileID: target, metadata: createdMetadata)
            try await btCreateOnboardProfilePrelude(device: device, target: target)
            try await btWriteOnboardProfileMetadata(device: device, target: target, metadata: createdMetadata)
            try await btApplyOnboardProfileMutation(
                device: device,
                profile: profile,
                target: target,
                mutation: createMutation.withoutMetadata
            )
            _ = try await validateOnboardProfileReadback(
                device: device,
                operation: "Bluetooth onboard profile create inventory",
                failureMessage: "Bluetooth onboard profile create readback did not list target \(target).",
                read: {
                    try await self.btListOnboardProfiles(device: device, profile: profile)
                },
                accepts: { inventory in
                    inventory.assignedProfileIDs.contains(target)
                }
            )
            do {
                return try await validateOnboardProfileReadback(
                    device: device,
                    operation: "Bluetooth onboard profile create snapshot",
                    failureMessage: "Bluetooth onboard profile create snapshot readback failed for target \(target).",
                    read: {
                        try await self.btReadOnboardProfile(device: device, profile: profile, target: target)
                    },
                    accepts: { snapshot in
                        snapshot.profileID == target && snapshot.metadata.name == createdMetadata.name
                    }
                )
            } catch {
                AppLog.warning(
                    "Bridge",
                    "Bluetooth onboard profile create metadata readback lagged after successful write device=\(device.id) target=\(target): \(error.localizedDescription)"
                )
                return projectedCreate
            }
        }
    }

    private func resolveCreateTargetForOnboardCreate(
        device: MouseDevice,
        profile: DeviceProfile,
        requested: Int?,
        replaceAssignedProfile: Bool
    ) async throws -> Int {
        if let requested, replaceAssignedProfile {
            guard requested >= OnboardProfileLimits.minimumStoredProfileID,
                  requested <= profile.onboardProfileCount else {
                throw BridgeError.commandFailed("Onboard profile \(requested) is outside the assignable profile range.")
            }
            return requested
        }
        let inventory = try await listOnboardProfiles(device: device)
        return try resolveCreateTarget(
            requested: requested,
            inventory: inventory,
            replaceAssignedProfile: replaceAssignedProfile
        )
    }

    func renameOnboardProfile(device: MouseDevice, profileID: Int, name: String) async throws -> OnboardProfileSnapshot {
        let profile = try mappedOnboardProfileSupport(for: device)

        switch device.transport {
        case .usb:
            return try await withUSBProfileSession(device: device) { session in
                let inventory = try self.usbReadOnboardProfileInventory(session, device, profile: profile)
                guard inventory.assignedProfiles.contains(UInt8(profileID)) else {
                    throw BridgeError.commandFailed("Onboard profile \(profileID) is not assigned.")
                }
                let currentRead = try self.usbReadOnboardProfileMetadataCandidate(
                    session,
                    device,
                    profileID: profileID,
                    requireKnownFields: true
                )
                let needsFullObjectRepair = currentRead.metadata == nil
                let currentMetadata = currentRead.metadata ?? OnboardProfileMetadata(
                    identifier: currentRead.parsed.identifier ?? UUID(),
                    name: currentRead.parsed.name ?? name,
                    owner: currentRead.parsed.owner ?? OnboardProfileMetadata.synapseCompatibleFallbackOwner
                )
                let renamed = self.usbMetadataForWrite(
                    session,
                    device,
                    metadata: currentMetadata.renamed(name),
                    excludingProfileID: profileID
                )
                let projected = OnboardProfileSnapshot(profileID: profileID, metadata: renamed)
                AppLog.debug(
                    "Bridge",
                    "USB onboard profile rename metadata-\(needsFullObjectRepair ? "repair" : "write") " +
                    "device=\(device.id) profile=\(profileID) currentName=\"\(currentMetadata.name)\" " +
                    "requestedName=\"\(renamed.name)\" uuid=\(currentMetadata.identifier.uuidString)"
                )
                if needsFullObjectRepair {
                    AppLog.warning(
                        "Bridge",
                        "USB onboard profile metadata identity is incomplete or has an invalid owner hash; repairing assigned profile metadata " +
                        "device=\(device.id) profile=\(profileID) requestedName=\"\(renamed.name)\""
                    )
                }
                try self.usbWriteOnboardProfileMetadata(
                    session,
                    device,
                    profileID: profileID,
                    metadata: renamed,
                    mode: needsFullObjectRepair ? "repair" : "rename"
                )
                let metadata = try self.validateUSBOnboardProfileReadback(
                    device: device,
                    operation: "USB onboard profile rename",
                    failureMessage: "USB onboard profile rename readback did not match profile \(profileID).",
                    read: {
                        try self.usbReadOnboardProfileMetadata(
                            session,
                            device,
                            profileID: profileID,
                            requireKnownFields: true
                        )
                    },
                    accepts: { metadata in
                        metadata.identifier == renamed.identifier &&
                            metadata.name == renamed.name &&
                            metadata.owner == renamed.owner
                    }
                )
                return projected.renamed(metadata)
            }
        case .bluetooth:
            let inventory = try await listOnboardProfiles(device: device)
            guard inventory.assignedProfileIDs.contains(profileID) else {
                throw BridgeError.commandFailed("Onboard profile \(profileID) is not assigned.")
            }
            let parsed = try await btReadOnboardProfileMetadataFields(
                device: device,
                target: profileID
            )
            let currentMetadata = Self.completeBluetoothOnboardProfileMetadata(parsed) ?? OnboardProfileMetadata(
                identifier: parsed.identifier ?? UUID(),
                name: parsed.name ?? name,
                owner: parsed.owner ?? OnboardProfileMetadata.synapseCompatibleFallbackOwner
            )
            let renamed = await btMetadataForWrite(
                device: device,
                profile: profile,
                metadata: currentMetadata.renamed(name),
                excludingProfileID: profileID
            )
            let projected = OnboardProfileSnapshot(profileID: profileID, metadata: renamed)
            try await btWriteOnboardProfileMetadata(device: device, target: profileID, metadata: renamed)
            do {
                let metadata = try await validateOnboardProfileReadback(
                    device: device,
                    operation: "Bluetooth onboard profile rename",
                    failureMessage: "Bluetooth onboard profile rename readback did not match target \(profileID).",
                    read: {
                        try await self.btReadOnboardProfileMetadata(
                            device: device,
                            target: profileID,
                            requireKnownFields: true
                        )
                    },
                    accepts: { metadata in
                        metadata.identifier == renamed.identifier &&
                            metadata.name == renamed.name &&
                            metadata.owner == renamed.owner
                    }
                )
                return projected.renamed(metadata)
            } catch {
                AppLog.warning(
                    "Bridge",
                    "Bluetooth onboard profile rename readback lagged after successful write device=\(device.id) target=\(profileID): \(error.localizedDescription)"
                )
                return projected
            }
        }
    }

    func updateOnboardProfile(
        device: MouseDevice,
        profileID: Int,
        mutation: OnboardProfileMutation
    ) async throws -> OnboardProfileSnapshot {
        let profile = try mappedOnboardProfileSupport(for: device)
        guard profileID >= 0, profileID <= profile.onboardProfileCount else {
            throw BridgeError.commandFailed("Onboard profile \(profileID) is outside the supported profile range.")
        }

        switch device.transport {
        case .usb:
            return try await withUSBProfileSession(device: device) { session in
                let activeBeforeMutation = try? self.usbReadActiveOnboardProfileID(session, device)
                if let metadata = mutation.metadata {
                    let metadataForWrite = self.usbMetadataForWrite(
                        session,
                        device,
                        metadata: metadata,
                        excludingProfileID: profileID
                    )
                    try self.usbWriteOnboardProfileMetadata(session, device, profileID: profileID, metadata: metadataForWrite)
                }
                let dpiWriteContext = mutation.dpi == nil ? nil : try? self.usbReadOnboardProfileDPI(
                    session,
                    device,
                    profileID: profileID
                )
                try self.usbApplyOnboardProfileMutation(
                    session,
                    device,
                    profile: profile,
                    profileID: profileID,
                    mutation: mutation.withoutMetadata,
                    dpiWriteContext: dpiWriteContext
                )
                if activeBeforeMutation == profileID {
                    _ = try self.usbWriteActiveOnboardProfileID(session, device, profileID: profileID)
                }
                return try self.usbReadOnboardProfile(session, device, profile: profile, profileID: profileID)
            }
        case .bluetooth:
            if let metadata = mutation.metadata {
                let metadataForWrite = await btMetadataForWrite(
                    device: device,
                    profile: profile,
                    metadata: metadata,
                    excludingProfileID: profileID
                )
                try await btWriteOnboardProfileMetadata(device: device, target: profileID, metadata: metadataForWrite)
            }
            try await btApplyOnboardProfileMutation(
                device: device,
                profile: profile,
                target: profileID,
                mutation: mutation.withoutMetadata
            )
            return try await btReadOnboardProfile(device: device, profile: profile, target: profileID)
        }
    }

    func deleteOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileInventory {
        let profile = try mappedOnboardProfileSupport(for: device)
        guard profileID >= 2 else {
            throw BridgeError.commandFailed("The base onboard profile cannot be deleted.")
        }

        switch device.transport {
        case .usb:
            return try await withUSBProfileSession(device: device) { session in
                AppLog.debug(
                    "Bridge",
                    "USB onboard profile delete start device=\(device.id) profile=\(profileID)"
                )
                let response = try self.perform(
                    session,
                    device,
                    classID: 0x05,
                    cmdID: 0x03,
                    size: 0x01,
                    args: USBHIDProtocol.onboardProfileDeleteArgs(profile: UInt8(profileID))
                )
                guard let response,
                      USBHIDProtocol.onboardProfileDeleteAccepted(from: response, profile: UInt8(profileID)) else {
                    let status = response.map { String(format: "0x%02X", $0[0]) } ?? "nil"
                    AppLog.warning(
                        "Bridge",
                        "USB onboard profile delete rejected device=\(device.id) profile=\(profileID) status=\(status)"
                    )
                    throw BridgeError.commandFailed("USB onboard profile delete was rejected.")
                }
                let inventory = try self.validateUSBOnboardProfileReadback(
                    device: device,
                    operation: "USB onboard profile delete",
                    failureMessage: "USB onboard profile delete readback still lists profile \(profileID).",
                    read: {
                        try self.usbListOnboardProfiles(session, device, profile: profile)
                    },
                    accepts: { inventory in
                        !inventory.assignedProfileIDs.contains(profileID)
                    }
                )
                AppLog.debug(
                    "Bridge",
                    "USB onboard profile delete ok device=\(device.id) profile=\(profileID) " +
                    "assigned=\(inventory.assignedProfileIDs.map(String.init).joined(separator: ","))"
                )
                return inventory
            }
        case .bluetooth:
            let req = nextBTReq()
            let header = BLEVendorProtocol.buildWriteHeader(
                req: req,
                payloadLength: 0x00,
                key: .profileTargetDelete(target: UInt8(profileID))
            )
            let notifies = try await btExchange([header], timeout: 0.9, device: device)
            guard btAckSuccess(notifies: notifies, req: req) else {
                throw BridgeError.commandFailed("Bluetooth onboard profile delete was rejected.")
            }
            return try await validateOnboardProfileReadback(
                device: device,
                operation: "Bluetooth onboard profile delete",
                failureMessage: "Bluetooth onboard profile delete readback still lists target \(profileID).",
                read: {
                    try await self.btListOnboardProfiles(device: device, profile: profile)
                },
                accepts: { inventory in
                    !inventory.assignedProfileIDs.contains(profileID)
                }
            )
        }
    }

    func activateOnboardProfile(device: MouseDevice, profileID: Int) async throws -> MouseState {
        let profile = try mappedOnboardProfileSupport(for: device)
        guard profileID >= 1, profileID <= profile.onboardProfileCount else {
            throw BridgeError.commandFailed("Onboard profile \(profileID) is outside the supported profile range.")
        }

        let start = Date()
        AppLog.debug("Bridge", "activate onboard profile start device=\(device.id) transport=\(device.transport.rawValue) profile=\(profileID)")
        let assigned: [Int]
        switch device.transport {
        case .usb:
            assigned = try await withUSBProfileSession(device: device) { session in
                try self.usbReadOnboardProfileInventory(session, device, profile: profile).assignedProfiles.map(Int.init)
            }
        case .bluetooth:
            assigned = try await btReadOnboardProfileTargets(device: device, profile: profile)
        }
        guard assigned.contains(profileID) else {
            throw BridgeError.commandFailed("Onboard profile \(profileID) is not assigned.")
        }

        let activated: Int
        switch device.transport {
        case .usb:
            activated = try await withUSBProfileSession(device: device) { session in
                try self.usbWriteActiveOnboardProfileID(session, device, profileID: profileID)
            }
        case .bluetooth:
            let req = nextBTReq()
            let header = BLEVendorProtocol.buildWriteHeader(
                req: req,
                payloadLength: 0x01,
                key: .profileActiveTargetSet()
            )
            let notifies = try await btExchange(
                [header, BLEVendorProtocol.Key.profileActiveTargetSetPayload(target: UInt8(profileID))],
                timeout: 0.9,
                device: device
            )
            guard btAckSuccess(notifies: notifies, req: req) else {
                throw BridgeError.commandFailed("Bluetooth onboard profile selector was rejected.")
            }
            activated = try await validateOnboardProfileReadback(
                device: device,
                operation: "Bluetooth active onboard profile selector",
                failureMessage: "Bluetooth active target readback did not match target \(profileID).",
                read: {
                    try await self.btReadActiveOnboardProfileID(device: device) ?? -1
                },
                accepts: { active in
                    active == profileID
                }
            )
        }
        AppLog.debug(
            "Bridge",
            "activate onboard profile ok device=\(device.id) profile=\(profileID) active=\(activated) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s"
        )
        return storeProjectedActiveOnboardProfileState(
            device: device,
            profile: profile,
            activeProfileID: activated
        )
    }

    func refreshActiveOnboardProfile(device: MouseDevice) async throws -> MouseState {
        let profile = try mappedOnboardProfileSupport(for: device)
        return try await refreshActiveOnboardProfile(device: device, profile: profile)
    }
}
