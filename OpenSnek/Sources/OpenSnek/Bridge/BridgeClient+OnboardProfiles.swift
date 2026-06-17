import Foundation
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

private struct USBOnboardProfileMetadataRead {
    let parsed: USBHIDProtocol.OnboardProfileMetadata
    let metadata: OnboardProfileMetadata?
}

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
        let inventory = try await listOnboardProfiles(device: device)
        let target = try resolveCreateTarget(
            requested: targetProfileID,
            inventory: inventory,
            replaceAssignedProfile: replaceAssignedProfile
        )
        var createMutation = mutation
        if createMutation.metadata == nil {
            createMutation.metadata = OnboardProfileMetadata(name: "Profile \(target)")
        }
        if createMutation.needsMappedContentFill {
            let activeSnapshot = try? await readOnboardProfile(device: device, profileID: 0)
            createMutation = createMutation.fillingMissingMappedContent(from: activeSnapshot)
        }
        let createdMetadata = createMutation.metadata!
        switch device.transport {
        case .usb:
            return try await withUSBProfileSession(device: device) { session in
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
                try self.usbApplyOnboardProfileMutation(
                    session,
                    device,
                    profile: profile,
                    profileID: target,
                    mutation: createMutation.withoutMetadata
                )
                _ = try self.retryUSBOnboardProfileReadback(
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
                return try self.retryUSBOnboardProfileReadback(
                    device: device,
                    operation: "USB onboard profile create snapshot",
                    failureMessage: "USB onboard profile create snapshot readback failed for profile \(target).",
                    attempts: 8,
                    read: {
                        try self.usbReadOnboardProfile(session, device, profile: profile, profileID: target)
                    },
                    accepts: { snapshot in
                        snapshot.profileID == target && snapshot.metadata.name == createdMetadata.name
                    }
                )
            }
        case .bluetooth:
            let projectedCreate = createMutation.projectedSnapshot(profileID: target, metadata: createdMetadata)
            try await btCreateOnboardProfilePrelude(device: device, target: target)
            try await btWriteOnboardProfileMetadata(device: device, target: target, metadata: createdMetadata)
            try await btApplyOnboardProfileMutation(
                device: device,
                profile: profile,
                target: target,
                mutation: createMutation.withoutMetadata
            )
            _ = try await retryOnboardProfileReadback(
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
                return try await retryOnboardProfileReadback(
                    device: device,
                    operation: "Bluetooth onboard profile create snapshot",
                    failureMessage: "Bluetooth onboard profile create snapshot readback failed for target \(target).",
                    attempts: 8,
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
                    name: currentRead.parsed.name ?? name,
                    owner: currentRead.parsed.owner ?? "OpenSnek"
                )
                let renamed = currentMetadata.renamed(name)
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
                        "USB onboard profile metadata UUID is invalid; repairing assigned profile metadata " +
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
                let metadata = try self.retryUSBOnboardProfileReadback(
                    device: device,
                    operation: "USB onboard profile rename",
                    failureMessage: "USB onboard profile rename readback did not match profile \(profileID).",
                    attempts: 5,
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
            let currentMetadata = try await btReadOnboardProfileMetadata(
                device: device,
                target: profileID,
                requireKnownFields: true
            )
            let renamed = currentMetadata.renamed(name)
            let projected = OnboardProfileSnapshot(profileID: profileID, metadata: renamed)
            try await btWriteOnboardProfileMetadata(device: device, target: profileID, metadata: renamed)
            do {
                let metadata = try await retryOnboardProfileReadback(
                    device: device,
                    operation: "Bluetooth onboard profile rename",
                    failureMessage: "Bluetooth onboard profile rename readback did not match target \(profileID).",
                    attempts: 3,
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
                if let metadata = mutation.metadata {
                    try self.usbWriteOnboardProfileMetadata(session, device, profileID: profileID, metadata: metadata)
                }
                try self.usbApplyOnboardProfileMutation(
                    session,
                    device,
                    profile: profile,
                    profileID: profileID,
                    mutation: mutation.withoutMetadata
                )
                return try self.usbReadOnboardProfile(session, device, profile: profile, profileID: profileID)
            }
        case .bluetooth:
            if let metadata = mutation.metadata {
                try await btWriteOnboardProfileMetadata(device: device, target: profileID, metadata: metadata)
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
                let inventory = try self.retryUSBOnboardProfileReadback(
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
            return try await retryOnboardProfileReadback(
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
                let response = try self.perform(
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
                return try self.retryUSBOnboardProfileReadback(
                    device: device,
                    operation: "USB active onboard profile selector",
                    failureMessage: "USB active profile readback did not match profile \(profileID).",
                    attempts: 6,
                    read: {
                        try self.usbReadActiveOnboardProfileID(session, device) ?? -1
                    },
                    accepts: { active in
                        active == profileID
                    }
                )
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
            activated = try await retryOnboardProfileReadback(
                device: device,
                operation: "Bluetooth active onboard profile selector",
                failureMessage: "Bluetooth active target readback did not match target \(profileID).",
                attempts: 6,
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

        var firstError: Error?
        for session in sessions {
            do {
                let value = try session.withExclusiveDeviceAccess {
                    try operation(session)
                }
                deviceSessions[device.id] = session
                return value
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        throw firstError ?? BridgeError.commandFailed("USB onboard profile operation failed.")
    }

    func retryUSBOnboardProfileReadback<T>(
        device: MouseDevice,
        operation: String,
        failureMessage: String,
        attempts: Int = 4,
        read: () throws -> T,
        accepts: (T) -> Bool
    ) throws -> T {
        var firstError: Error?
        let totalAttempts = max(1, attempts)
        for attempt in 0..<totalAttempts {
            do {
                let value = try read()
                if accepts(value) {
                    return value
                }
                if firstError == nil {
                    firstError = BridgeError.commandFailed(failureMessage)
                }
                AppLog.debug(
                    "Bridge",
                    "\(operation) readback validation failed device=\(device.id) attempt=\(attempt + 1)/\(totalAttempts)"
                )
            } catch {
                if firstError == nil {
                    firstError = error
                }
                AppLog.debug(
                    "Bridge",
                    "\(operation) readback attempt \(attempt + 1)/\(totalAttempts) failed device=\(device.id): \(error.localizedDescription)"
                )
            }

            if attempt + 1 < totalAttempts {
                let backoffMs = UInt64(120 + (attempt * 120))
                Thread.sleep(forTimeInterval: Double(backoffMs) / 1000.0)
            }
        }
        throw firstError ?? BridgeError.commandFailed(failureMessage)
    }

    func retryOnboardProfileReadback<T>(
        device: MouseDevice,
        operation: String,
        failureMessage: String,
        attempts: Int = 4,
        read: () async throws -> T,
        accepts: (T) -> Bool
    ) async throws -> T {
        var firstError: Error?
        let totalAttempts = max(1, attempts)
        for attempt in 0..<totalAttempts {
            do {
                let value = try await read()
                if accepts(value) {
                    return value
                }
                if firstError == nil {
                    firstError = BridgeError.commandFailed(failureMessage)
                }
                AppLog.debug(
                    "Bridge",
                    "\(operation) readback validation failed device=\(device.id) attempt=\(attempt + 1)/\(totalAttempts)"
                )
            } catch {
                if firstError == nil {
                    firstError = error
                }
                AppLog.debug(
                    "Bridge",
                    "\(operation) readback attempt \(attempt + 1)/\(totalAttempts) failed device=\(device.id): \(error.localizedDescription)"
                )
            }

            if attempt + 1 < totalAttempts {
                let backoffMs = UInt64(120 + (attempt * 120))
                try? await Task.sleep(nanoseconds: backoffMs * 1_000_000)
            }
        }
        throw firstError ?? BridgeError.commandFailed(failureMessage)
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

    private func usbReadOnboardProfileMetadataCandidate(
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
        let metadata = parsed.identifier.map {
            OnboardProfileMetadata(
                identifier: $0,
                name: parsed.name ?? "Profile \(profileID)",
                owner: parsed.owner ?? "OpenSnek"
            )
        }
        return USBOnboardProfileMetadataRead(parsed: parsed, metadata: metadata)
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
            throw BridgeError.commandFailed("USB onboard profile metadata read did not include a UUID for profile \(profileID).")
        }
        return read.metadata ?? OnboardProfileMetadata(
            name: read.parsed.name ?? "Profile \(profileID)",
            owner: read.parsed.owner ?? "OpenSnek"
        )
    }

    func usbWriteOnboardProfileMetadata(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profileID: Int,
        metadata: OnboardProfileMetadata,
        mode: String = "write"
    ) throws {
        let bytes = USBHIDProtocol.buildOnboardProfileMetadata(
            identifier: metadata.identifier,
            name: metadata.name,
            owner: metadata.owner
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
                    if let readback = try? retryUSBOnboardProfileReadback(
                        device: device,
                        operation: "USB onboard profile metadata tail",
                        failureMessage: "USB onboard profile metadata tail readback did not match profile \(profileID).",
                        attempts: 6,
                        read: {
                            try self.usbReadOnboardProfileMetadata(
                                session,
                                device,
                                profileID: profileID,
                                requireKnownFields: true
                            )
                        },
                        accepts: { readback in
                            readback.identifier == metadata.identifier &&
                                readback.name == metadata.name &&
                                readback.owner == metadata.owner
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
                args: [storage, 0, 0, 0, 0, 0, 0],
                allowTxnRescan: true
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
            args: [UInt8(profileID)],
            allowTxnRescan: true
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
                ),
                allowTxnRescan: true
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
                    profile: UInt8(profileID),
                    slot: UInt8(slot),
                    hypershift: 0x00,
                    functionBlock: block
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
            0x00,
        ]
        var firstError: Error?
        for attempt in 0..<4 {
            do {
                if let response = try perform(session, device, classID: 0x04, cmdID: 0x05, size: 0x07, args: args),
                   response[0] == 0x02 {
                    return
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
            if attempt < 3 {
                usleep(useconds_t(70_000 + (attempt * 40_000)))
            }
        }
        if let firstError {
            throw firstError
        }
        throw BridgeError.commandFailed("USB onboard profile DPI scalar write failed.")
    }

    func usbWriteOnboardProfileDPIStages(
        _ session: USBHIDControlSession,
        _ device: MouseDevice,
        profileID: Int,
        dpi: OnboardDPIProfileSnapshot
    ) throws {
        let count = max(1, min(5, dpi.pairs.count))
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
        var firstError: Error?
        for attempt in 0..<4 {
            do {
                if let response = try perform(session, device, classID: 0x04, cmdID: 0x06, size: 0x26, args: args),
                   response[0] == 0x02 {
                    return
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
            if attempt < 3 {
                usleep(useconds_t(70_000 + (attempt * 40_000)))
            }
        }
        if let firstError {
            throw firstError
        }
        throw BridgeError.commandFailed("USB onboard profile DPI stage write failed.")
    }

    func btReadPayload(
        device: MouseDevice,
        key: BLEVendorProtocol.Key,
        requestPayload: Data? = nil,
        timeout: TimeInterval = 0.6
    ) async throws -> Data? {
        let req = nextBTReq()
        let writes: [Data]
        if let requestPayload {
            writes = [
                BLEVendorProtocol.buildWriteHeader(
                    req: req,
                    payloadLength: UInt8(requestPayload.count),
                    key: key
                ),
                requestPayload,
            ]
        } else {
            writes = [BLEVendorProtocol.buildReadHeader(req: req, key: key)]
        }
        let notifies = try await btExchange(writes, timeout: timeout, device: device)
        return BLEVendorProtocol.parsePayloadFrames(notifies: notifies, req: req)
    }

    func btWriteAck(
        device: MouseDevice,
        key: BLEVendorProtocol.Key,
        payload: Data = Data(),
        timeout: TimeInterval = 0.9
    ) async throws -> Bool {
        let req = nextBTReq()
        let header = BLEVendorProtocol.buildWriteHeader(
            req: req,
            payloadLength: UInt8(payload.count),
            key: key
        )
        let writes = payload.isEmpty ? [header] : [header, payload]
        let notifies = try await btExchange(writes, timeout: timeout, device: device)
        return btAckSuccess(notifies: notifies, req: req)
    }

    func btListOnboardProfiles(device: MouseDevice, profile: DeviceProfile) async throws -> OnboardProfileInventory {
        let assigned = try await btReadOnboardProfileTargets(device: device, profile: profile)
        let active = try await btReadActiveOnboardProfileID(device: device) ?? 1
        let summaries = assigned.map { target in
            OnboardProfileSummary(
                profileID: target,
                metadata: nil,
                isAssigned: true,
                isActive: target == active,
                isBaseProfile: target == 1
            )
        }
        return OnboardProfileInventory(
            activeProfileID: active,
            maxProfileID: profile.onboardProfileCount,
            assignedProfileIDs: assigned,
            profiles: summaries
        )
    }

    func btReadOnboardProfileTargets(device: MouseDevice, profile: DeviceProfile) async throws -> [Int] {
        guard let targetPayload = try await btReadPayload(device: device, key: .profileTargetsGet()) else {
            throw BridgeError.commandFailed("Bluetooth onboard profile inventory read failed.")
        }
        return BLEVendorProtocol.parseProfileTargets(payload: targetPayload, maxProfileID: profile.onboardProfileCount)
    }

    func btReadActiveOnboardProfileID(device: MouseDevice) async throws -> Int? {
        guard let payload = try await btReadPayload(device: device, key: .profileActiveTargetGet()) else {
            return nil
        }
        return BLEVendorProtocol.parseActiveTarget(payload: payload)
    }

    func btReadOnboardProfile(
        device: MouseDevice,
        profile: DeviceProfile,
        target: Int,
        includeMetadata: Bool = true,
        includeButtonBindings: Bool = true
    ) async throws -> OnboardProfileSnapshot {
        let metadata: OnboardProfileMetadata
        if !includeMetadata {
            metadata = OnboardProfileMetadata(name: target == 0 ? "Active Profile" : "Profile \(target)")
        } else if target == 0 {
            metadata = (try? await btReadOnboardProfileMetadata(device: device, target: target))
                ?? OnboardProfileMetadata(name: "Active Profile")
        } else {
            metadata = try await btReadOnboardProfileMetadata(device: device, target: target)
        }
        let dpi = try await btReadOnboardProfileDPI(device: device, target: target)
        let bindings = includeButtonBindings
            ? try await btReadOnboardProfileButtons(device: device, profile: profile, target: target)
            : [:]
        let brightness = try await btReadOnboardProfileBrightness(device: device, target: target)
        let colors = try await btReadOnboardProfileStaticColors(device: device, target: target)
        return OnboardProfileSnapshot(
            profileID: target,
            metadata: metadata,
            dpi: dpi,
            buttonBindings: bindings,
            brightnessByLEDID: brightness,
            staticColorByLEDID: colors
        )
    }

    func btReadOnboardProfileMetadata(
        device: MouseDevice,
        target: Int,
        requireKnownFields: Bool = false
    ) async throws -> OnboardProfileMetadata {
        var chunks: [BLEVendorProtocol.ProfileMetadataChunk] = []
        for offset in BLEVendorProtocol.onboardProfileMetadataChunkOffsets {
            let length = min(
                BLEVendorProtocol.onboardProfileMetadataChunkDataLength,
                BLEVendorProtocol.onboardProfileMetadataLength - offset
            )
            guard let payload = try await btReadPayload(
                device: device,
                key: .profileMetadataGet(target: UInt8(target)),
                requestPayload: BLEVendorProtocol.profileMetadataReadRequest(offset: offset, length: length)
            ), let chunk = BLEVendorProtocol.profileMetadataChunk(from: payload, expectedOffset: offset) else {
                throw BridgeError.commandFailed("Bluetooth onboard profile metadata read failed at offset \(offset).")
            }
            chunks.append(chunk)
        }
        let parsed = BLEVendorProtocol.parseProfileMetadata(BLEVendorProtocol.mergeProfileMetadataChunks(chunks))
        if let metadata = Self.completeBluetoothOnboardProfileMetadata(parsed) {
            return metadata
        }
        if requireKnownFields {
            throw BridgeError.commandFailed(
                "Bluetooth onboard profile metadata read did not include complete UUID/name/owner fields for target \(target)."
            )
        }
        return OnboardProfileMetadata(
            identifier: parsed.identifier ?? UUID(),
            name: parsed.name ?? "Profile \(target)",
            owner: parsed.owner ?? "OpenSnek"
        )
    }

    static func completeBluetoothOnboardProfileMetadata(
        _ parsed: USBHIDProtocol.OnboardProfileMetadata
    ) -> OnboardProfileMetadata? {
        guard let identifier = parsed.identifier,
              let name = parsed.name,
              let owner = parsed.owner else {
            return nil
        }
        return OnboardProfileMetadata(identifier: identifier, name: name, owner: owner)
    }

    func btWriteOnboardProfileMetadata(device: MouseDevice, target: Int, metadata: OnboardProfileMetadata) async throws {
        let bytes = BLEVendorProtocol.buildProfileMetadata(
            identifier: metadata.identifier,
            name: metadata.name,
            owner: metadata.owner
        )
        for offset in BLEVendorProtocol.onboardProfileMetadataChunkOffsets {
            let payload = BLEVendorProtocol.profileMetadataWritePayload(offset: offset, metadata: bytes)
            guard try await btWriteAck(
                device: device,
                key: .profileMetadataSet(target: UInt8(target)),
                payload: payload
            ) else {
                throw BridgeError.commandFailed("Bluetooth onboard profile metadata write failed at offset \(offset).")
            }
        }
    }

    func btReadOnboardProfileDPI(device: MouseDevice, target: Int) async throws -> OnboardDPIProfileSnapshot? {
        let scalarPayload = try await btReadPayload(device: device, key: .dpiScalarGet(target: UInt8(target)))
        let scalar = scalarPayload.flatMap {
            BLEVendorProtocol.parseDpiScalarPair(blob: $0)
        }
        if let projection = try await btReadPayload(device: device, key: .dpiProjectionGet(target: UInt8(target))),
           let parsed = BLEVendorProtocol.parseDpiStageSnapshot(blob: projection) {
            return OnboardDPIProfileSnapshot(
                scalar: scalar,
                activeStage: parsed.active,
                pairs: Array(parsed.pairs.prefix(parsed.count)),
                stageIDs: parsed.stageIDs,
                marker: parsed.marker
            )
        }
        let pairPayload = try await btReadPayload(device: device, key: .dpiPairListGet(target: UInt8(target)))
        let pairs = pairPayload.flatMap {
            BLEVendorProtocol.parseDpiPairList(blob: $0)
        } ?? scalar.map { [$0] } ?? []
        let tokenPayload = try await btReadPayload(device: device, key: .dpiStageTokenGet(target: UInt8(target)))
        let token = tokenPayload?.first
        guard scalar != nil || !pairs.isEmpty else { return nil }
        let active = token.flatMap { raw in
            let ids = Array((0..<pairs.count).map { UInt8($0 + 1) })
            return BLEVendorProtocol.resolveActiveStage(activeRaw: Int(raw), stageIDs: ids, count: max(1, pairs.count))
        }
        return OnboardDPIProfileSnapshot(
            scalar: scalar,
            activeStage: active,
            pairs: pairs,
            stageIDs: Array((0..<pairs.count).map { UInt8($0 + 1) }),
            marker: 0x03
        )
    }

    func btReadOnboardProfileButtons(
        device: MouseDevice,
        profile: DeviceProfile,
        target: Int
    ) async throws -> [Int: ButtonBindingDraft] {
        var bindings: [Int: ButtonBindingDraft] = [:]
        for slot in profile.buttonLayout.writableSlots {
            guard let payload = try await btReadPayload(
                device: device,
                key: .buttonBindGet(target: UInt8(target), slot: UInt8(slot))
            ), let block = BLEVendorProtocol.extractBluetoothFunctionBlock(
                payload: payload,
                target: UInt8(target),
                slot: UInt8(slot),
                profileID: device.profile_id
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

    func btReadOnboardProfileBrightness(device: MouseDevice, target: Int) async throws -> [Int: Int] {
        var values: [Int: Int] = [:]
        for ledID in bluetoothLightingLEDIDs(device: device) {
            guard let value = try await btReadPayload(
                device: device,
                key: .profileLightingBrightnessGet(target: UInt8(target), ledID: ledID)
            )?.first else {
                continue
            }
            values[Int(ledID)] = Int(value)
        }
        return values
    }

    func btReadOnboardProfileStaticColors(device: MouseDevice, target: Int) async throws -> [Int: RGBPatch] {
        var values: [Int: RGBPatch] = [:]
        for ledID in bluetoothLightingLEDIDs(device: device) {
            guard let payload = try await btReadPayload(
                device: device,
                key: .profileLightingZoneStateGet(target: UInt8(target), ledID: ledID)
            ), let color = BLEVendorProtocol.parseV3ProLightingZoneStatePayload(payload) else {
                continue
            }
            values[Int(ledID)] = color
        }
        return values
    }

    func btCreateOnboardProfilePrelude(device: MouseDevice, target: Int) async throws {
        guard try await btWriteAck(
            device: device,
            key: .profileTargetDelete(target: UInt8(target)),
            payload: Data()
        ) else {
            throw BridgeError.commandFailed("Bluetooth onboard profile create delete step failed.")
        }
        guard try await btWriteAck(
            device: device,
            key: .profileTargetPrepare(target: UInt8(target)),
            payload: Data([0x00])
        ) else {
            throw BridgeError.commandFailed("Bluetooth onboard profile create prepare step failed.")
        }
        guard let statusPayload = try await btReadPayload(
            device: device,
            key: .profileTargetStatusGet(target: UInt8(target))
        ), statusPayload.first == 0x01 else {
            throw BridgeError.commandFailed("Bluetooth onboard profile create status readback failed.")
        }
        guard try await btWriteAck(
            device: device,
            key: .profileTargetApply(target: UInt8(target)),
            payload: Data([0x00])
        ) else {
            throw BridgeError.commandFailed("Bluetooth onboard profile create apply step failed.")
        }
        guard try await btWriteAck(
            device: device,
            key: .profileTargetCommit(target: UInt8(target)),
            payload: Data()
        ) else {
            throw BridgeError.commandFailed("Bluetooth onboard profile create commit step failed.")
        }
    }

    func btApplyOnboardProfileMutation(
        device: MouseDevice,
        profile: DeviceProfile,
        target: Int,
        mutation: OnboardProfileMutation
    ) async throws {
        if let dpi = mutation.dpi, !dpi.pairs.isEmpty {
            try await btWriteOnboardProfileDPI(device: device, target: target, dpi: dpi)
        }
        if let bindings = mutation.buttonBindings {
            for (slot, draft) in bindings where profile.buttonLayout.isEditable(slot) {
                let payload = BLEVendorProtocol.retargetButtonPayload(
                    BLEVendorProtocol.buildButtonPayload(
                        slot: UInt8(slot),
                        kind: draft.kind,
                        hidKey: UInt8(max(0, min(255, draft.hidKey))),
                        hidModifiers: UInt8(max(0, min(255, draft.hidModifiers))),
                        turboEnabled: draft.turboEnabled && draft.kind.supportsTurbo,
                        turboRate: UInt16(max(1, min(255, draft.turboRate)))
                    ),
                    target: UInt8(target),
                    slot: UInt8(slot)
                )
                guard try await btWriteAck(
                    device: device,
                    key: .buttonBindSet(target: UInt8(target), slot: UInt8(slot)),
                    payload: payload
                ) else {
                    throw BridgeError.commandFailed("Bluetooth onboard profile button write failed for slot \(slot).")
                }
            }
        }
        if let brightnessByLEDID = mutation.brightnessByLEDID, !brightnessByLEDID.isEmpty {
            guard try await btWriteAck(
                device: device,
                key: .profileTargetPrepare(target: UInt8(target)),
                payload: Data([0x00])
            ) else {
                throw BridgeError.commandFailed("Bluetooth onboard profile brightness prepare failed.")
            }
            let brightness = brightnessByLEDID.values.max() ?? 0
            guard try await btWriteAck(
                device: device,
                key: .storedLightingBrightnessSet(target: UInt8(target)),
                payload: Data([UInt8(max(0, min(255, brightness)))])
            ) else {
                throw BridgeError.commandFailed("Bluetooth onboard profile brightness write failed.")
            }
        }
        if let colors = mutation.staticColorByLEDID {
            for (ledID, color) in colors {
                let payload = BLEVendorProtocol.buildV3ProLightingZoneStatePayload(
                    r: color.r,
                    g: color.g,
                    b: color.b
                )
                guard try await btWriteAck(
                    device: device,
                    key: .profileLightingZoneStateSet(target: UInt8(target), ledID: UInt8(ledID)),
                    payload: payload
                ) else {
                    throw BridgeError.commandFailed("Bluetooth onboard profile static color write failed for LED \(ledID).")
                }
            }
        }
    }

    func btWriteOnboardProfileDPI(device: MouseDevice, target: Int, dpi: OnboardDPIProfileSnapshot) async throws {
        let count = max(1, min(5, dpi.pairs.count))
        let active = max(0, min(count - 1, dpi.activeStage ?? 0))
        let pairs = Array(dpi.pairs.prefix(5))
        let payload = BLEVendorProtocol.buildDpiStagePayload(
            active: active,
            count: count,
            pairs: pairs,
            marker: dpi.marker ?? 0x03,
            stageIDs: dpi.stageIDs.isEmpty ? nil : dpi.stageIDs
        )
        guard try await btWriteAck(
            device: device,
            key: .storedDpiStagesSet(target: UInt8(target)),
            payload: payload
        ) else {
            throw BridgeError.commandFailed("Bluetooth onboard profile DPI stage write failed.")
        }
        let scalar = dpi.scalar ?? pairs[active]
        let scalarPayload = Data([
            UInt8(scalar.x & 0xFF),
            UInt8((scalar.x >> 8) & 0xFF),
            UInt8(scalar.y & 0xFF),
            UInt8((scalar.y >> 8) & 0xFF),
            0x00,
            0x00,
        ])
        guard try await btWriteAck(
            device: device,
            key: .storedDpiScalarSet(target: UInt8(target)),
            payload: scalarPayload
        ) else {
            throw BridgeError.commandFailed("Bluetooth onboard profile DPI scalar write failed.")
        }
    }

    func refreshActiveOnboardProfile(device: MouseDevice, profile: DeviceProfile) async throws -> MouseState {
        let rawActive: Int
        switch device.transport {
        case .usb:
            rawActive = try await withUSBProfileSession(device: device) { session in
                try self.usbReadActiveOnboardProfileID(session, device) ?? 1
            }
        case .bluetooth:
            rawActive = try await btReadActiveOnboardProfileID(device: device) ?? 1
        }
        let active = max(1, min(profile.onboardProfileCount, rawActive))
        return storeProjectedActiveOnboardProfileState(
            device: device,
            profile: profile,
            activeProfileID: active
        )
    }

    func storeProjectedActiveOnboardProfileState(
        device: MouseDevice,
        profile: DeviceProfile,
        activeProfileID: Int
    ) -> MouseState {
        let previous = lastStateByDeviceID[device.id]
        let active = max(1, min(profile.onboardProfileCount, activeProfileID))
        let state = MouseState(
            device: previous?.device ?? DeviceSummary(
                id: device.id,
                product_name: device.product_name,
                serial: device.serial,
                transport: device.transport,
                firmware: device.firmware
            ),
            connection: previous?.connection ?? device.connectionLabel,
            battery_percent: previous?.battery_percent,
            charging: previous?.charging,
            dpi: previous?.dpi,
            dpi_stages: previous?.dpi_stages ?? DpiStages(active_stage: nil, values: nil),
            poll_rate: previous?.poll_rate,
            sleep_timeout: previous?.sleep_timeout,
            device_mode: previous?.device_mode,
            low_battery_threshold_raw: previous?.low_battery_threshold_raw,
            scroll_mode: previous?.scroll_mode,
            scroll_acceleration: previous?.scroll_acceleration,
            scroll_smart_reel: previous?.scroll_smart_reel,
            active_onboard_profile: active,
            onboard_profile_count: profile.onboardProfileCount,
            led_value: previous?.led_value,
            capabilities: previous?.capabilities ?? Capabilities(
                dpi_stages: true,
                poll_rate: device.transport == .usb,
                power_management: true,
                button_remap: true,
                lighting: device.showsLightingControls
            )
        )
        lastStateByDeviceID[device.id] = state
        return state
    }

    func storeProjectedActiveOnboardProfileState(
        device: MouseDevice,
        profile: DeviceProfile,
        activeProfileID: Int,
        snapshot: OnboardProfileSnapshot
    ) -> MouseState {
        let previous = lastStateByDeviceID[device.id]
        let active = max(1, min(profile.onboardProfileCount, activeProfileID))
        let state = stateFromActiveOnboardProfileSnapshot(
            device: device,
            profile: profile,
            activeProfileID: active,
            snapshot: snapshot,
            previous: previous
        )
        lastStateByDeviceID[device.id] = state
        return state
    }

    func stateFromActiveOnboardProfileSnapshot(
        device: MouseDevice,
        profile: DeviceProfile,
        activeProfileID: Int,
        snapshot: OnboardProfileSnapshot,
        previous: MouseState?
    ) -> MouseState {
        let activeStage = snapshot.dpi?.activeStage ?? previous?.dpi_stages.active_stage
        let pairs = snapshot.dpi?.pairs
        let values = pairs?.map(\.x) ?? previous?.dpi_stages.values
        let activePair: DpiPair? = {
            if let pairs, let activeStage, pairs.indices.contains(activeStage) {
                return pairs[activeStage]
            }
            return snapshot.dpi?.scalar ?? previous?.dpi
        }()
        return MouseState(
            device: previous?.device ?? DeviceSummary(
                id: device.id,
                product_name: device.product_name,
                serial: device.serial,
                transport: device.transport,
                firmware: device.firmware
            ),
            connection: previous?.connection ?? device.connectionLabel,
            battery_percent: previous?.battery_percent,
            charging: previous?.charging,
            dpi: activePair,
            dpi_stages: DpiStages(active_stage: activeStage, values: values, pairs: pairs ?? previous?.dpi_stages.pairs),
            poll_rate: previous?.poll_rate,
            sleep_timeout: previous?.sleep_timeout,
            device_mode: previous?.device_mode,
            low_battery_threshold_raw: previous?.low_battery_threshold_raw,
            scroll_mode: snapshot.scrollMode ?? previous?.scroll_mode,
            scroll_acceleration: snapshot.scrollAcceleration ?? previous?.scroll_acceleration,
            scroll_smart_reel: snapshot.scrollSmartReel ?? previous?.scroll_smart_reel,
            active_onboard_profile: activeProfileID,
            onboard_profile_count: profile.onboardProfileCount,
            led_value: snapshot.brightnessByLEDID.values.max() ?? previous?.led_value,
            capabilities: previous?.capabilities ?? Capabilities(
                dpi_stages: true,
                poll_rate: device.transport == .usb,
                power_management: true,
                button_remap: true,
                lighting: device.showsLightingControls
            )
        )
    }
}

private extension OnboardProfileSnapshot {
    func renamed(_ metadata: OnboardProfileMetadata) -> OnboardProfileSnapshot {
        OnboardProfileSnapshot(
            profileID: profileID,
            metadata: metadata,
            dpi: dpi,
            buttonBindings: buttonBindings,
            brightnessByLEDID: brightnessByLEDID,
            staticColorByLEDID: staticColorByLEDID,
            scrollMode: scrollMode,
            scrollAcceleration: scrollAcceleration,
            scrollSmartReel: scrollSmartReel
        )
    }
}

private extension OnboardProfileMutation {
    var needsMappedContentFill: Bool {
        dpi == nil ||
            buttonBindings == nil ||
            brightnessByLEDID == nil ||
            staticColorByLEDID == nil ||
            scrollMode == nil ||
            scrollAcceleration == nil ||
            scrollSmartReel == nil
    }

    var withoutMetadata: OnboardProfileMutation {
        OnboardProfileMutation(
            metadata: nil,
            dpi: dpi,
            buttonBindings: buttonBindings,
            brightnessByLEDID: brightnessByLEDID,
            staticColorByLEDID: staticColorByLEDID,
            scrollMode: scrollMode,
            scrollAcceleration: scrollAcceleration,
            scrollSmartReel: scrollSmartReel
        )
    }

    func fillingMissingMappedContent(from snapshot: OnboardProfileSnapshot?) -> OnboardProfileMutation {
        guard let snapshot else { return self }
        return OnboardProfileMutation(
            metadata: metadata,
            dpi: dpi ?? snapshot.dpi,
            buttonBindings: buttonBindings ?? snapshot.buttonBindings,
            brightnessByLEDID: brightnessByLEDID ?? snapshot.brightnessByLEDID,
            staticColorByLEDID: staticColorByLEDID ?? snapshot.staticColorByLEDID,
            scrollMode: scrollMode ?? snapshot.scrollMode,
            scrollAcceleration: scrollAcceleration ?? snapshot.scrollAcceleration,
            scrollSmartReel: scrollSmartReel ?? snapshot.scrollSmartReel
        )
    }

    func projectedSnapshot(profileID: Int, metadata: OnboardProfileMetadata) -> OnboardProfileSnapshot {
        OnboardProfileSnapshot(
            profileID: profileID,
            metadata: metadata,
            dpi: dpi,
            buttonBindings: buttonBindings ?? [:],
            brightnessByLEDID: brightnessByLEDID ?? [:],
            staticColorByLEDID: staticColorByLEDID ?? [:],
            scrollMode: scrollMode,
            scrollAcceleration: scrollAcceleration,
            scrollSmartReel: scrollSmartReel
        )
    }
}
