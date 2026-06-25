import Foundation
import OpenSnekCore
import OpenSnekProtocols

/// Adds USB profiles behavior to `OpenSnekProbe`.
extension OpenSnekProbe {
    /// Stores USB profile read record data.
    private struct USBProfileReadRecord {
        let profile: UInt8
        var scalar: DpiPair?
        var stagePairs: [DpiPair] = []
        var stageIDs: [UInt8] = []
        var activeToken: UInt8?
        var brightnessByLED: [UInt8: Int] = [:]
        var buttonBySlot: [UInt8: [UInt8]] = [:]
    }

    /// Stores USB profile brightness record data.
    private struct USBProfileBrightnessRecord {
        let target: USBLightingTargetDescriptor
        let value: Int
        let raw: [UInt8]
    }

    /// Captures USB profile writable state.
    private struct USBProfileWritableSnapshot {
        let profile: UInt8
        let scalar: DpiPair
        let scalarRaw: [UInt8]
        let stagesRaw: [UInt8]
        let stagePairs: [DpiPair]
        let activeToken: UInt8
        let brightness: [USBProfileBrightnessRecord]
    }

    /// Carries USB profile clone request data.
    struct USBProfileCloneRequest {
        let usb: USBProbeClient
        let sourceProfile: UInt8
        let targetProfile: UInt8
        let metadataMode: USBProfileCloneMetadataMode
        let targetName: String?
        let targetIdentifier: UUID?
        let cloneMappedContent: Bool
        let buttonSlots: [UInt8]
    }

    static func printUSBProfileReadSweep(usb: USBProbeClient, profiles: [UInt8], buttonSlots: [UInt8], includeEffective: Bool) throws {
        if let summary = try usb.readProfileSummaryRaw() {
            let activeHint = summary.first.map { String($0) } ?? "nil"
            let countHint = summary.count > 2 ? String(summary[2]) : "nil"
            print("summary class=00 cmd=87 payload=\(hexString(summary)) activeHint=\(activeHint) countHint=\(countHint)")
        } else {
            print("summary class=00 cmd=87 read_failed")
        }

        if let profileCount = try usb.readProfileCount() { print("profile-count class=05 cmd=80 value=\(profileCount)") } else { print("profile-count class=05 cmd=80 read_failed") }

        if let inventory = try usb.readProfileInventory() {
            let profiles = inventory.assignedProfiles.map { String(format: "0x%02x", $0) }.joined(separator: ",")
            print("profile-inventory class=05 cmd=81 maxProfile=0x\(String(format: "%02x", inventory.maxProfileID)) assigned=[\(profiles)]")
        } else {
            print("profile-inventory class=05 cmd=81 read_failed")
        }

        if let active = try usb.readActiveProfileID() { print("active-profile class=05 cmd=84 value=\(active) \(usbProfileLabel(active))") } else { print("active-profile class=05 cmd=84 read_failed") }

        let lightingTargets = usb.profileLightingTargets()
        print("lighting-leds ids=\(lightingTargets.map { String(format: "0x%02x", $0.ledID) }.joined(separator: ","))")

        let readProfiles = uniqueByteList((includeEffective ? [0x00, 0x01] : []) + profiles)
        var records: [USBProfileReadRecord] = []

        for profile in readProfiles {
            var record = USBProfileReadRecord(profile: profile)
            let label = usbProfileLabel(profile)

            if profile >= 0x02 {
                if let metadataRead = try usb.readProfileMetadata(profile: profile) {
                    let metadata = metadataRead.metadata
                    let chunkOffsets = metadataRead.chunks.map { String(format: "0x%04x", $0.offset) }.joined(separator: ",")
                    let uuid = metadata.identifier?.uuidString.lowercased() ?? "nil"
                    let name = metadata.name.map { "\"\($0)\"" } ?? "nil"
                    let owner = metadata.owner ?? "nil"
                    print("metadata \(label) chunks=\(metadataRead.chunks.count) offsets=[\(chunkOffsets)] uuid=\(uuid) name=\(name) owner=\(owner)")
                } else {
                    print("metadata \(label) read_failed")
                }
            }

            if let scalar = try usb.readProfileDPIScalar(profile: profile) {
                record.scalar = scalar.pair
                let pair = scalar.pair.map { "\($0.x)x\($0.y)" } ?? "nil"
                print("dpi-scalar \(label) pair=\(pair) raw=\(hexString(scalar.raw))")
            } else {
                print("dpi-scalar \(label) read_failed")
            }

            if let stages = try usb.readProfileDPIStages(profile: profile) {
                record.stagePairs = stages.pairs
                record.stageIDs = stages.stageIDs
                record.activeToken = stages.activeToken
                let stageIDs = stages.stageIDs.map { String(format: "0x%02x", $0) }.joined(separator: ",")
                print("dpi-stages \(label) activeToken=0x\(String(format: "%02x", stages.activeToken)) " + "stageIDs=[\(stageIDs)] pairs=\(describeDpiPairs(stages.pairs)) raw=\(hexString(stages.raw))")
            } else {
                print("dpi-stages \(label) read_failed")
            }

            for target in lightingTargets {
                if let brightness = try usb.readProfileLightingBrightness(profile: profile, ledID: target.ledID) {
                    if let value = brightness.brightness { record.brightnessByLED[target.ledID] = value }
                    let value = brightness.brightness.map(String.init) ?? "nil"
                    print("brightness \(label) zone=\(target.zoneID) led=0x\(String(format: "%02x", target.ledID)) " + "value=\(value) raw=\(hexString(brightness.raw))")
                } else {
                    print("brightness \(label) zone=\(target.zoneID) led=0x\(String(format: "%02x", target.ledID)) read_failed")
                }
            }

            for slot in buttonSlots {
                if let block = try usb.readButtonFunction(profile: profile, slot: slot) {
                    record.buttonBySlot[slot] = block
                    print("button \(label) slot=\(slot) raw=\(hexString(block)) \(describeUSBFunctionBlock(block))")
                } else {
                    print("button \(label) slot=\(slot) read_failed")
                }
            }

            records.append(record)
        }

        guard includeEffective, let effective = records.first(where: { $0.profile == 0x00 }) else { return }
        let effectiveFingerprint = usbProfileFingerprint(effective)
        let matches = records.filter { profiles.contains($0.profile) && usbProfileFingerprint($0) == effectiveFingerprint }.map(\.profile)
        if matches.isEmpty {
            print("fingerprint effective=\(usbProfileLabel(0x00)) match=none")
        } else if matches.count == 1, let match = matches.first {
            print("fingerprint effective=\(usbProfileLabel(0x00)) match=\(usbProfileLabel(match))")
        } else {
            print("fingerprint effective=\(usbProfileLabel(0x00)) ambiguous=[" + matches.map(usbProfileLabel).joined(separator: ", ") + "]")
        }
    }

    static func usbProfileLabel(_ profile: UInt8) -> String {
        switch profile {
        case 0x00: return "effective(profile=0)"
        case 0x01: return "base(profile=1)"
        default: return "stored-slot=\(Int(profile) - 1)(profile=\(profile))"
        }
    }

    private static func usbProfileFingerprint(_ record: USBProfileReadRecord) -> String {
        let scalar = record.scalar.map { "\($0.x)x\($0.y)" } ?? "nil"
        let stages = record.stagePairs.map { "\($0.x)x\($0.y)" }.joined(separator: ",")
        let brightness = record.brightnessByLED.keys.sorted().map { key in "0x\(String(format: "%02x", key))=\(record.brightnessByLED[key] ?? -1)" }.joined(separator: ",")
        let buttons = record.buttonBySlot.keys.sorted().map { key in "0x\(String(format: "%02x", key))=\(hexString(record.buttonBySlot[key] ?? []))" }.joined(separator: ",")
        return [scalar, stages, brightness, buttons].joined(separator: "|")
    }

    static func verifyUSBProfileSameValueWrites(usb: USBProbeClient, profile: UInt8) throws {
        let label = usbProfileLabel(profile)

        guard let scalarBefore = try usb.readProfileDPIScalar(profile: profile), let pairBefore = scalarBefore.pair else { throw ProbeError.protocolError("Unable to read DPI scalar before same-value write") }
        let scalarWrite = try usb.writeProfileDPIScalar(profile: profile, pair: pairBefore)
        guard let scalarAfter = try usb.readProfileDPIScalar(profile: profile), let pairAfter = scalarAfter.pair else { throw ProbeError.protocolError("Unable to read DPI scalar after same-value write") }
        print("verify-write dpi-scalar \(label) " + "before=\(pairBefore.x)x\(pairBefore.y) after=\(pairAfter.x)x\(pairAfter.y) " + "rawBefore=\(hexString(scalarBefore.raw)) rawAfter=\(hexString(scalarAfter.raw)) status=\(scalarWrite && pairAfter == pairBefore ? "ok" : "mismatch")")
        guard scalarWrite, pairAfter == pairBefore else { throw ProbeError.protocolError("DPI scalar same-value write did not round-trip") }

        guard let stagesBefore = try usb.readProfileDPIStages(profile: profile) else { throw ProbeError.protocolError("Unable to read DPI stages before same-value write") }
        let stagesWrite = try usb.writeProfileDPIStagesRaw(stagesBefore.raw)
        guard let stagesAfter = try usb.readProfileDPIStages(profile: profile) else { throw ProbeError.protocolError("Unable to read DPI stages after same-value write") }
        let stagesMatch = stagesAfter.activeToken == stagesBefore.activeToken && stagesAfter.stageIDs == stagesBefore.stageIDs && stagesAfter.pairs == stagesBefore.pairs
        print(
            "verify-write dpi-stages \(label) " + "beforeToken=0x\(String(format: "%02x", stagesBefore.activeToken)) " + "afterToken=0x\(String(format: "%02x", stagesAfter.activeToken)) " + "before=\(describeDpiPairs(stagesBefore.pairs)) after=\(describeDpiPairs(stagesAfter.pairs)) "
                + "status=\(stagesWrite && stagesMatch ? "ok" : "mismatch")")
        guard stagesWrite, stagesMatch else { throw ProbeError.protocolError("DPI stages same-value write did not round-trip") }

        for target in usb.profileLightingTargets() {
            guard let brightnessBefore = try usb.readProfileLightingBrightness(profile: profile, ledID: target.ledID), let valueBefore = brightnessBefore.brightness else {
                throw ProbeError.protocolError("Unable to read brightness before same-value write for LED 0x\(String(format: "%02x", target.ledID))")
            }
            let brightnessWrite = try usb.writeProfileLightingBrightness(profile: profile, ledID: target.ledID, brightness: valueBefore)
            guard let brightnessAfter = try usb.readProfileLightingBrightness(profile: profile, ledID: target.ledID), let valueAfter = brightnessAfter.brightness else {
                throw ProbeError.protocolError("Unable to read brightness after same-value write for LED 0x\(String(format: "%02x", target.ledID))")
            }
            print(
                "verify-write brightness \(label) zone=\(target.zoneID) led=0x\(String(format: "%02x", target.ledID)) " + "before=\(valueBefore) after=\(valueAfter) " + "rawBefore=\(hexString(brightnessBefore.raw)) rawAfter=\(hexString(brightnessAfter.raw)) "
                    + "status=\(brightnessWrite && valueAfter == valueBefore ? "ok" : "mismatch")")
            guard brightnessWrite, valueAfter == valueBefore else { throw ProbeError.protocolError("Brightness same-value write did not round-trip for LED 0x\(String(format: "%02x", target.ledID))") }
        }
    }

    static func verifyUSBProfileChangedValueWrites(usb: USBProbeClient, profile: UInt8) throws {
        let label = usbProfileLabel(profile)
        let original = try readUSBProfileWritableSnapshot(usb: usb, profile: profile)
        let changedScalar = DpiPair(x: changedUSBProfileDPIValue(original.scalar.x), y: changedUSBProfileDPIValue(original.scalar.y))
        let changedStagesRaw = try changedUSBProfileStageRaw(original.stagesRaw)
        let changedBrightness = Dictionary(uniqueKeysWithValues: original.brightness.map { record in (record.target.ledID, changedUSBProfileBrightnessValue(record.value)) })

        var wroteAny = false
        do {
            let scalarWrite = try usb.writeProfileDPIScalar(profile: profile, pair: changedScalar)
            wroteAny = wroteAny || scalarWrite
            guard let scalarAfter = try usb.readProfileDPIScalar(profile: profile), let scalarPairAfter = scalarAfter.pair else { throw ProbeError.protocolError("Unable to read DPI scalar after changed-value write") }
            print(
                "verify-changed dpi-scalar \(label) " + "original=\(original.scalar.x)x\(original.scalar.y) changed=\(changedScalar.x)x\(changedScalar.y) " + "after=\(scalarPairAfter.x)x\(scalarPairAfter.y) rawAfter=\(hexString(scalarAfter.raw)) "
                    + "status=\(scalarWrite && scalarPairAfter == changedScalar ? "ok" : "mismatch")")
            guard scalarWrite, scalarPairAfter == changedScalar else { throw ProbeError.protocolError("DPI scalar changed-value write did not round-trip") }

            let stagesWrite = try usb.writeProfileDPIStagesRaw(changedStagesRaw)
            wroteAny = wroteAny || stagesWrite
            guard let stagesAfter = try usb.readProfileDPIStages(profile: profile) else { throw ProbeError.protocolError("Unable to read DPI stages after changed-value write") }
            print(
                "verify-changed dpi-stages \(label) " + "original=\(describeDpiPairs(original.stagePairs)) after=\(describeDpiPairs(stagesAfter.pairs)) " + "expectedRaw=\(hexString(changedStagesRaw)) rawAfter=\(hexString(stagesAfter.raw)) "
                    + "status=\(stagesWrite && stagesAfter.raw == changedStagesRaw ? "ok" : "mismatch")")
            guard stagesWrite, stagesAfter.raw == changedStagesRaw else { throw ProbeError.protocolError("DPI stages changed-value write did not round-trip") }

            for record in original.brightness {
                guard let changedValue = changedBrightness[record.target.ledID] else { continue }
                let brightnessWrite = try usb.writeProfileLightingBrightness(profile: profile, ledID: record.target.ledID, brightness: changedValue)
                wroteAny = wroteAny || brightnessWrite
                guard let brightnessAfter = try usb.readProfileLightingBrightness(profile: profile, ledID: record.target.ledID), let valueAfter = brightnessAfter.brightness else {
                    throw ProbeError.protocolError("Unable to read brightness after changed-value write for LED 0x\(String(format: "%02x", record.target.ledID))")
                }
                print(
                    "verify-changed brightness \(label) zone=\(record.target.zoneID) led=0x\(String(format: "%02x", record.target.ledID)) " + "original=\(record.value) changed=\(changedValue) after=\(valueAfter) " + "rawAfter=\(hexString(brightnessAfter.raw)) "
                        + "status=\(brightnessWrite && valueAfter == changedValue ? "ok" : "mismatch")")
                guard brightnessWrite, valueAfter == changedValue else { throw ProbeError.protocolError("Brightness changed-value write did not round-trip for LED 0x\(String(format: "%02x", record.target.ledID))") }
            }

            try restoreUSBProfileWritableSnapshot(usb: usb, snapshot: original, label: label)
        } catch {
            if wroteAny {
                print("verify-changed restore-after-error \(label) starting")
                do { try restoreUSBProfileWritableSnapshot(usb: usb, snapshot: original, label: label) } catch { print("verify-changed restore-after-error \(label) failed=\(error.localizedDescription)") }
            }
            throw error
        }
    }

    static func cloneUSBProfile(_ request: USBProfileCloneRequest) throws {
        let usb = request.usb
        let sourceProfile = request.sourceProfile
        let targetProfile = request.targetProfile
        let sourceLabel = usbProfileLabel(sourceProfile)
        let targetLabel = usbProfileLabel(targetProfile)
        guard let metadataRead = try usb.readProfileMetadataBytes(profile: sourceProfile) else { throw ProbeError.protocolError("Unable to read source profile metadata") }
        let sourceMetadata = metadataRead.metadata
        let sourceUUID = sourceMetadata.identifier?.uuidString.lowercased() ?? "nil"
        let sourceName = sourceMetadata.name ?? "nil"
        let sourceOwner = sourceMetadata.owner ?? "nil"
        print("clone metadata-source \(sourceLabel) " + "uuid=\(sourceUUID) name=\"\(sourceName)\" owner=\(sourceOwner)")
        guard let sourceIdentifier = sourceMetadata.identifier, let sourceName = sourceMetadata.name, let compatibleSourceOwner = OnboardProfileMetadata.synapseCompatibleOwner(from: sourceMetadata.owner) else { throw ProbeError.protocolError("Source profile metadata is not Synapse-compatible") }

        let targetMetadataBefore = try usb.readProfileMetadataBytes(profile: targetProfile)
        let metadataToWrite: [UInt8]
        let metadataExpectation: String
        switch request.metadataMode {
        case .exact:
            metadataToWrite = metadataRead.bytes
            metadataExpectation = "exact-source"
        case .repair:
            let repairedIdentifier = request.targetIdentifier ?? repairedTargetIdentifier(current: targetMetadataBefore?.metadata.identifier, source: sourceIdentifier)
            let repairedName = request.targetName ?? repairedTargetName(current: targetMetadataBefore?.metadata.name, source: sourceName, targetProfile: targetProfile)
            metadataToWrite = try repairedUSBProfileMetadataBytes(base: targetMetadataBefore?.bytes ?? metadataRead.bytes, identifier: repairedIdentifier, name: repairedName, owner: compatibleSourceOwner)
            metadataExpectation = "uuid=\(repairedIdentifier.uuidString.lowercased()) name=\"\(repairedName)\" owner=\(compatibleSourceOwner)"
        }

        print("clone metadata-plan \(targetLabel) mode=\(request.metadataMode.rawValue) expected=\(metadataExpectation)")
        let metadataWrite = try usb.writeProfileMetadataBytes(profile: targetProfile, metadata: metadataToWrite)
        guard let targetMetadataRead = try usb.readProfileMetadataBytes(profile: targetProfile) else { throw ProbeError.protocolError("Unable to read target profile metadata after clone") }
        let expectedMetadata = Array(metadataToWrite.prefix(USBHIDProtocol.onboardProfileMetadataLength))
        let actualMetadata = Array(targetMetadataRead.bytes.prefix(USBHIDProtocol.onboardProfileMetadataLength))
        let targetMetadata = targetMetadataRead.metadata
        print("clone metadata-target \(targetLabel) " + "uuid=\(targetMetadata.identifier?.uuidString.lowercased() ?? "nil") " + "name=\"\(targetMetadata.name ?? "nil")\" owner=\(targetMetadata.owner ?? "nil") " + "status=\(metadataWrite && actualMetadata == expectedMetadata ? "ok" : "mismatch")")
        guard metadataWrite, actualMetadata == expectedMetadata else { throw ProbeError.protocolError("Target profile metadata did not match source after clone") }

        guard request.cloneMappedContent else { return }

        guard let sourceScalar = try usb.readProfileDPIScalar(profile: sourceProfile), let sourcePair = sourceScalar.pair else { throw ProbeError.protocolError("Unable to read source DPI scalar") }
        let scalarWrite = try usb.writeProfileDPIScalar(profile: targetProfile, pair: sourcePair)
        guard let targetScalar = try usb.readProfileDPIScalar(profile: targetProfile), let targetPair = targetScalar.pair else { throw ProbeError.protocolError("Unable to read target DPI scalar after clone") }
        print("clone dpi-scalar \(sourceLabel)->\(targetLabel) " + "source=\(sourcePair.x)x\(sourcePair.y) target=\(targetPair.x)x\(targetPair.y) " + "status=\(scalarWrite && targetPair == sourcePair ? "ok" : "mismatch")")
        guard scalarWrite, targetPair == sourcePair else { throw ProbeError.protocolError("Target DPI scalar did not match source after clone") }

        guard let sourceStages = try usb.readProfileDPIStages(profile: sourceProfile) else { throw ProbeError.protocolError("Unable to read source DPI stages") }
        var retargetedStagesRaw = sourceStages.raw
        retargetedStagesRaw[0] = targetProfile
        let stagesWrite = try usb.writeProfileDPIStagesRaw(retargetedStagesRaw)
        guard let targetStages = try usb.readProfileDPIStages(profile: targetProfile) else { throw ProbeError.protocolError("Unable to read target DPI stages after clone") }
        print("clone dpi-stages \(sourceLabel)->\(targetLabel) " + "source=\(describeDpiPairs(sourceStages.pairs)) target=\(describeDpiPairs(targetStages.pairs)) " + "status=\(stagesWrite && targetStages.raw == retargetedStagesRaw ? "ok" : "mismatch")")
        guard stagesWrite, targetStages.raw == retargetedStagesRaw else { throw ProbeError.protocolError("Target DPI stages did not match source after clone") }

        for target in usb.profileLightingTargets() {
            guard let sourceBrightness = try usb.readProfileLightingBrightness(profile: sourceProfile, ledID: target.ledID), let sourceValue = sourceBrightness.brightness else { throw ProbeError.protocolError("Unable to read source brightness for LED 0x\(String(format: "%02x", target.ledID))") }
            let brightnessWrite = try usb.writeProfileLightingBrightness(profile: targetProfile, ledID: target.ledID, brightness: sourceValue)
            guard let targetBrightness = try usb.readProfileLightingBrightness(profile: targetProfile, ledID: target.ledID), let targetValue = targetBrightness.brightness else {
                throw ProbeError.protocolError("Unable to read target brightness for LED 0x\(String(format: "%02x", target.ledID)) after clone")
            }
            print("clone brightness \(sourceLabel)->\(targetLabel) zone=\(target.zoneID) " + "led=0x\(String(format: "%02x", target.ledID)) source=\(sourceValue) target=\(targetValue) " + "status=\(brightnessWrite && targetValue == sourceValue ? "ok" : "mismatch")")
            guard brightnessWrite, targetValue == sourceValue else { throw ProbeError.protocolError("Target brightness did not match source for LED 0x\(String(format: "%02x", target.ledID))") }
        }

        for slot in request.buttonSlots {
            guard let sourceBlock = try usb.readButtonFunction(profile: sourceProfile, slot: slot) else { throw ProbeError.protocolError("Unable to read source button slot \(slot)") }
            let buttonWrite = try usb.writeButtonFunction(profile: targetProfile, slot: slot, functionBlock: sourceBlock)
            guard let targetBlock = try usb.readButtonFunction(profile: targetProfile, slot: slot) else { throw ProbeError.protocolError("Unable to read target button slot \(slot) after clone") }
            print("clone button \(sourceLabel)->\(targetLabel) slot=\(slot) " + "source=\(hexString(sourceBlock)) target=\(hexString(targetBlock)) " + "status=\(buttonWrite && targetBlock == sourceBlock ? "ok" : "mismatch")")
            guard buttonWrite, targetBlock == sourceBlock else { throw ProbeError.protocolError("Target button slot \(slot) did not match source after clone") }
        }
    }

    static func repairedTargetIdentifier(current: UUID?, source: UUID) -> UUID {
        guard let current, current != source else { return UUID() }
        return current
    }

    static func repairedTargetName(current: String?, source: String, targetProfile: UInt8) -> String {
        if let current = current?.trimmingCharacters(in: .whitespacesAndNewlines), !current.isEmpty, current != source { return current }
        let fallback = "\(source) Copy \(targetProfile)"
        return String(fallback.prefix(0x74 - 0x10))
    }

    static func repairedUSBProfileMetadataBytes(base: [UInt8], identifier: UUID, name: String, owner: String) throws -> [UInt8] {
        guard OnboardProfileMetadata.isSynapseCompatibleOwner(owner) else { throw ProbeError.protocolError("Owner is not a Synapse-compatible 64-character hex string") }
        var metadata = Array(base.prefix(USBHIDProtocol.onboardProfileMetadataLength))
        if metadata.count < USBHIDProtocol.onboardProfileMetadataLength { metadata.append(contentsOf: repeatElement(0x00, count: USBHIDProtocol.onboardProfileMetadataLength - metadata.count)) }

        let guid = USBHIDProtocol.windowsGUIDBytes(from: identifier)
        for (index, byte) in guid.enumerated() where index < 16 { metadata[index] = byte }
        try writeASCIIField(name, into: &metadata, offset: 0x10, maxLength: 0x74 - 0x10, fieldName: "profile name")
        try writeASCIIField(owner, into: &metadata, offset: 0x74, maxLength: 64, fieldName: "profile owner")
        return metadata
    }

    static func writeASCIIField(_ value: String, into metadata: inout [UInt8], offset: Int, maxLength: Int, fieldName: String) throws {
        let bytes = try asciiBytes(value, maxLength: maxLength, fieldName: fieldName)
        let upperBound = min(metadata.count, offset + maxLength)
        guard offset >= 0, offset < upperBound else { return }
        for index in offset..<upperBound { metadata[index] = 0x00 }
        for (index, byte) in bytes.enumerated() { metadata[offset + index] = byte }
    }

    private static func readUSBProfileWritableSnapshot(usb: USBProbeClient, profile: UInt8) throws -> USBProfileWritableSnapshot {
        guard let scalarRead = try usb.readProfileDPIScalar(profile: profile), let scalar = scalarRead.pair else { throw ProbeError.protocolError("Unable to read stored-profile DPI scalar snapshot") }
        guard let stagesRead = try usb.readProfileDPIStages(profile: profile) else { throw ProbeError.protocolError("Unable to read stored-profile DPI stage snapshot") }
        var brightness: [USBProfileBrightnessRecord] = []
        for target in usb.profileLightingTargets() {
            guard let read = try usb.readProfileLightingBrightness(profile: profile, ledID: target.ledID), let value = read.brightness else { throw ProbeError.protocolError("Unable to read brightness snapshot for LED 0x\(String(format: "%02x", target.ledID))") }
            brightness.append(USBProfileBrightnessRecord(target: target, value: value, raw: read.raw))
        }
        return USBProfileWritableSnapshot(profile: profile, scalar: scalar, scalarRaw: scalarRead.raw, stagesRaw: stagesRead.raw, stagePairs: stagesRead.pairs, activeToken: stagesRead.activeToken, brightness: brightness)
    }

    private static func restoreUSBProfileWritableSnapshot(usb: USBProbeClient, snapshot: USBProfileWritableSnapshot, label: String) throws {
        let scalarWrite = try usb.writeProfileDPIScalar(profile: snapshot.profile, pair: snapshot.scalar)
        guard let scalarAfter = try usb.readProfileDPIScalar(profile: snapshot.profile), let scalarPairAfter = scalarAfter.pair else { throw ProbeError.protocolError("Unable to read DPI scalar after restore") }
        print("verify-restore dpi-scalar \(label) " + "restored=\(scalarPairAfter.x)x\(scalarPairAfter.y) rawAfter=\(hexString(scalarAfter.raw)) " + "status=\(scalarWrite && scalarPairAfter == snapshot.scalar ? "ok" : "mismatch")")
        guard scalarWrite, scalarPairAfter == snapshot.scalar else { throw ProbeError.protocolError("DPI scalar restore did not round-trip") }

        let stagesWrite = try usb.writeProfileDPIStagesRaw(snapshot.stagesRaw)
        guard let stagesAfter = try usb.readProfileDPIStages(profile: snapshot.profile) else { throw ProbeError.protocolError("Unable to read DPI stages after restore") }
        print("verify-restore dpi-stages \(label) " + "restored=\(describeDpiPairs(stagesAfter.pairs)) rawAfter=\(hexString(stagesAfter.raw)) " + "status=\(stagesWrite && stagesAfter.raw == snapshot.stagesRaw ? "ok" : "mismatch")")
        guard stagesWrite, stagesAfter.raw == snapshot.stagesRaw else { throw ProbeError.protocolError("DPI stages restore did not round-trip") }

        for record in snapshot.brightness {
            let brightnessWrite = try usb.writeProfileLightingBrightness(profile: snapshot.profile, ledID: record.target.ledID, brightness: record.value)
            guard let brightnessAfter = try usb.readProfileLightingBrightness(profile: snapshot.profile, ledID: record.target.ledID), let valueAfter = brightnessAfter.brightness else {
                throw ProbeError.protocolError("Unable to read brightness after restore for LED 0x\(String(format: "%02x", record.target.ledID))")
            }
            print("verify-restore brightness \(label) zone=\(record.target.zoneID) led=0x\(String(format: "%02x", record.target.ledID)) " + "restored=\(valueAfter) rawAfter=\(hexString(brightnessAfter.raw)) " + "status=\(brightnessWrite && valueAfter == record.value ? "ok" : "mismatch")")
            guard brightnessWrite, valueAfter == record.value else { throw ProbeError.protocolError("Brightness restore did not round-trip for LED 0x\(String(format: "%02x", record.target.ledID))") }
        }
    }

    static func changedUSBProfileDPIValue(_ value: Int) -> Int {
        if value <= 29_900 { return value + 100 }
        return max(100, value - 100)
    }

    static func changedUSBProfileBrightnessValue(_ value: Int) -> Int { value < 255 ? value + 1 : max(0, value - 1) }

    static func changedUSBProfileStageRaw(_ raw: [UInt8]) throws -> [UInt8] {
        guard raw.count >= 10 else { throw ProbeError.protocolError("DPI stage raw payload is too short to mutate safely") }
        var changed = raw
        let rowOffset = 3
        let originalX = (Int(raw[rowOffset + 1]) << 8) | Int(raw[rowOffset + 2])
        let originalY = (Int(raw[rowOffset + 3]) << 8) | Int(raw[rowOffset + 4])
        let changedX = changedUSBProfileDPIValue(originalX)
        let changedY = changedUSBProfileDPIValue(originalY)
        changed[rowOffset + 1] = UInt8((changedX >> 8) & 0xFF)
        changed[rowOffset + 2] = UInt8(changedX & 0xFF)
        changed[rowOffset + 3] = UInt8((changedY >> 8) & 0xFF)
        changed[rowOffset + 4] = UInt8(changedY & 0xFF)
        return changed
    }

}
