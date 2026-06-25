import Foundation
import OpenSnekCore
import OpenSnekProtocols

/// Adds commands behavior to `OpenSnekProbe`.
extension OpenSnekProbe {
    static func runBluetoothCommand(_ command: String, commandArgs: [String]) async throws {
        if try await runBluetoothGeneralCommand(command, commandArgs: commandArgs) { return }
        if try await runBluetoothProfileCommand(command, commandArgs: commandArgs) { return }
        if try await runBluetoothLightingCommand(command, commandArgs: commandArgs) { return }
        throw ProbeError.usage("Unknown command '\(command)'\n\(usageText)")
    }

    private static func runBluetoothGeneralCommand(_ command: String, commandArgs: [String]) async throws -> Bool {
        switch command {
        case "bt-info":
            let bridge = ProbeBridge()
            let summaries = await bridge.connectedPeripherals() ?? []
            if summaries.isEmpty { print("bt connected-peripherals: none") } else { for summary in summaries { print("bt peripheral name=\"\(summary.name ?? "")\" id=\(summary.identifier.uuidString)") } }
        case "bt-raw-read":
            let bridge = ProbeBridge()
            let parsed = try parseBTRawReadArgs(commandArgs)
            let result = try await bridge.rawRead(key: parsed.key, timeout: parsed.timeoutSeconds, preferredPeripheralName: parsed.preferredPeripheralName)
            print("bt-raw-read req=0x\(String(format: "%02x", result.req)) key=\(hexString(parsed.key)) name=\"\(parsed.preferredPeripheralName ?? "")\"")
            print(describeBTNotifyFrames(result.notifies))
            if let payload = result.payload {
                print("payload[\(payload.count)]: \(hexString(Array(payload)))")
                if let decoded = decodeBTButtonReadFunctionBlock(key: parsed.key, payload: payload, notifies: result.notifies) { print("decoded-button-function[\(decoded.count)]: \(hexString(decoded))") }
            } else {
                print("payload: nil")
            }
        case "bt-raw-write":
            let bridge = ProbeBridge()
            let parsed = try parseBTRawWriteArgs(commandArgs)
            let result = try await bridge.rawWrite(key: parsed.key, payload: Data(parsed.payload), timeout: parsed.timeoutSeconds, preferredPeripheralName: parsed.preferredPeripheralName)
            print("bt-raw-write req=0x\(String(format: "%02x", result.req)) key=\(hexString(parsed.key)) payload=\(hexString(parsed.payload)) name=\"\(parsed.preferredPeripheralName ?? "")\"")
            print(describeBTNotifyFrames(result.notifies))
            if let ack = result.ack { print("ack status=0x\(String(format: "%02x", ack.status)) payloadLength=\(ack.payloadLength)") } else { print("ack: nil") }
        default: return false
        }
        return true
    }

    private static func runBluetoothProfileCommand(_ command: String, commandArgs: [String]) async throws -> Bool {
        switch command {
        case "bt-profile-read":
            let bridge = ProbeBridge()
            let parsed = try parseBTProfileReadArgs(commandArgs)
            print("bt-profile-read name=\"\(parsed.preferredPeripheralName ?? "")\" " + "targets=\(parsed.targets.map { String($0) }.joined(separator: ",")) " + "buttonSlots=\(parsed.buttonSlots.map { String($0) }.joined(separator: ","))")
            try await printBTProfileReadSweep(
                BTProfileReadSweepRequest(session: BTProfileProbeSession(bridge: bridge, preferredPeripheralName: parsed.preferredPeripheralName, timeoutSeconds: parsed.timeoutSeconds), targets: parsed.targets, buttonSlots: parsed.buttonSlots, includeLiveButtons: parsed.includeLiveButtons))
        case "bt-profile-active-set":
            let bridge = ProbeBridge()
            let parsed = try parseBTProfileActiveSetArgs(commandArgs)
            let readKey = BLEVendorProtocol.Key.profileActiveTargetGet().bytes
            let before = try await bridge.rawRead(key: readKey, timeout: parsed.timeoutSeconds, preferredPeripheralName: parsed.preferredPeripheralName)
            let write = try await bridge.rawWrite(key: BLEVendorProtocol.Key.profileActiveTargetSet().bytes, payload: BLEVendorProtocol.Key.profileActiveTargetSetPayload(target: parsed.target), timeout: parsed.timeoutSeconds, preferredPeripheralName: parsed.preferredPeripheralName)
            let after = try await bridge.rawRead(key: readKey, timeout: parsed.timeoutSeconds, preferredPeripheralName: parsed.preferredPeripheralName)
            let beforeTarget = before.payload?.first
            let afterTarget = after.payload?.first
            print("bt-profile-active-set target=\(parsed.target) \(btProfileTargetLabel(parsed.target)) " + "before=\(beforeTarget.map(String.init) ?? "nil") " + "ack=\(describeBTAckStatus(write.ack)) " + "after=\(afterTarget.map(String.init) ?? "nil")")
            guard write.ack?.status == 0x02, afterTarget == parsed.target else { throw ProbeError.protocolError("BT active-target selector did not select target \(parsed.target)") }
        case "bt-profile-create":
            let bridge = ProbeBridge()
            let parsed = try parseBTProfileCreateArgs(commandArgs)
            print("bt-profile-create \(btProfileTargetLabel(parsed.target)) " + "profileName=\"\(parsed.profileName)\" guid=\(parsed.guid.uuidString.lowercased()) " + "dpi=\(parsed.values) active=\(parsed.active + 1) brightness=\(parsed.brightness)")
            try await createBTProfileTarget(
                BTProfileCreateRequest(
                    session: BTProfileProbeSession(bridge: bridge, preferredPeripheralName: parsed.preferredPeripheralName, timeoutSeconds: parsed.timeoutSeconds), target: parsed.target, guid: parsed.guid, profileName: parsed.profileName, owner: parsed.owner, values: parsed.values,
                    active: parsed.active, brightness: parsed.brightness))
        case "bt-profile-button-read":
            let bridge = ProbeBridge()
            let parsed = try parseBTProfileButtonReadArgs(commandArgs)
            let key = BLEVendorProtocol.Key.buttonBindGet(target: parsed.target, slot: parsed.buttonSlot).bytes
            let result = try await bridge.rawRead(key: key, timeout: parsed.timeoutSeconds, preferredPeripheralName: parsed.preferredPeripheralName)
            print("bt-profile-button-read \(btProfileTargetLabel(parsed.target)) " + "slot=\(parsed.buttonSlot) key=\(hexString(key)) name=\"\(parsed.preferredPeripheralName ?? "")\"")
            print(describeBTNotifyFrames(result.notifies))
            print(describeBTProfileButtonRead(key: key, payload: result.payload, notifies: result.notifies))
        case "bt-profile-button-set":
            let bridge = ProbeBridge()
            let parsed = try parseBTProfileButtonSetArgs(commandArgs)
            let storedKey = BLEVendorProtocol.Key.buttonBindSet(target: parsed.target, slot: parsed.buttonSlot).bytes
            let storedPayload = parsed.payload
            let storedResult = try await bridge.rawWrite(key: storedKey, payload: Data(storedPayload), timeout: parsed.timeoutSeconds, preferredPeripheralName: parsed.preferredPeripheralName)
            print("bt-profile-button-set \(btProfileTargetLabel(parsed.target)) " + "slot=\(parsed.buttonSlot) key=\(hexString(storedKey)) payload=\(hexString(storedPayload)) " + "status=\(describeBTAckStatus(storedResult.ack))")
            if parsed.projectLive {
                let livePayload = Array(BLEVendorProtocol.retargetButtonPayload(Data(storedPayload), target: 0x01, slot: parsed.buttonSlot))
                let liveKey = BLEVendorProtocol.Key.buttonBindSet(target: 0x01, slot: parsed.buttonSlot).bytes
                let liveResult = try await bridge.rawWrite(key: liveKey, payload: Data(livePayload), timeout: parsed.timeoutSeconds, preferredPeripheralName: parsed.preferredPeripheralName)
                print("bt-profile-button-set live-projection slot=\(parsed.buttonSlot) " + "key=\(hexString(liveKey)) payload=\(hexString(livePayload)) status=\(describeBTAckStatus(liveResult.ack))")
            }
            let readbackTargets = parsed.projectLive ? [parsed.target, 0x01] : [parsed.target]
            for target in readbackTargets {
                let readKey = BLEVendorProtocol.Key.buttonBindGet(target: target, slot: parsed.buttonSlot).bytes
                let readback = try await bridge.rawRead(key: readKey, timeout: parsed.timeoutSeconds, preferredPeripheralName: parsed.preferredPeripheralName)
                print("readback \(btProfileTargetLabel(target)) slot=\(parsed.buttonSlot)")
                print(describeBTProfileButtonRead(key: readKey, payload: readback.payload, notifies: readback.notifies))
            }
        case "bt-profile-hid-watch", "bt-profile-cycle-watch":
            let parsed = try parseBTProfileHIDWatchArgs(commandArgs)
            let probe = try BTProfileHIDReportProbe(productID: parsed.productID, preferredPeripheralName: parsed.preferredPeripheralName)
            print("bt-profile-hid-watch candidates=\(probe.candidateCount) " + "duration=\(String(format: "%.1f", parsed.durationSeconds))s " + "maxReports=\(parsed.maxReports.map(String.init) ?? "unlimited")")
            for line in probe.describeCandidates() { print(line) }
            let reportCount = try await probe.capture(duration: parsed.durationSeconds, maxReports: parsed.maxReports) { event in
                let hex = event.report.map { String(format: "%02x", $0) }.joined(separator: " ")
                print(String(format: "[+%.3fs] candidate[%d] usage=%@ input=%d feature=%d class=%@ report[%d]=%@", event.elapsedSeconds, event.candidateIndex, event.usageLabel, event.maxInputReportSize, event.maxFeatureReportSize, event.classification.label, event.report.count, hex))
            }
            print("bt-profile-hid-watch complete reports=\(reportCount)")
        case "bt-profile-watch":
            let bridge = ProbeBridge()
            let parsed = try parseBTProfileWatchArgs(commandArgs)
            print("bt-profile-watch name=\"\(parsed.preferredPeripheralName ?? "")\" " + "slot=\(parsed.buttonSlot) polls=\(parsed.samples) pollMs=\(parsed.pollMs)")
            print("note: this fingerprints the live projected Bluetooth layer, not the persistent stored slots.")

            var previous: BTProfileWatchSnapshot?
            var seenSignatures: [String: Int] = [:]

            for pollIndex in 0..<parsed.samples {
                let snapshot = try await readBTProfileWatchSnapshot(bridge: bridge, preferredPeripheralName: parsed.preferredPeripheralName, timeoutSeconds: parsed.timeoutSeconds, buttonSlot: parsed.buttonSlot)
                let signatureID =
                    seenSignatures[snapshot.signature]
                    ?? {
                        let next = seenSignatures.count + 1
                        seenSignatures[snapshot.signature] = next
                        return next
                    }()

                let prefix: String
                if let previous, previous.signature != snapshot.signature { prefix = "CHANGE" } else if previous == nil { prefix = "BASE" } else { prefix = "SAME" }

                print("[poll \(pollIndex + 1)/\(parsed.samples)] \(prefix) " + "signature#\(signatureID) \(snapshot.summary)")

                if let previous, previous.signature != snapshot.signature {
                    print("  from: \(previous.summary)")
                    print("  to:   \(snapshot.summary)")
                }

                previous = snapshot
                if pollIndex + 1 < parsed.samples, parsed.pollMs > 0 { try await Task.sleep(nanoseconds: UInt64(parsed.pollMs) * 1_000_000) }
            }
        default: return false
        }
        return true
    }

    private static func runBluetoothLightingCommand(_ command: String, commandArgs: [String]) async throws -> Bool {
        switch command {
        case "bt-lighting-info":
            let bridge = ProbeBridge()
            let parsed = try parseBTLightingZoneArgs(commandArgs)
            let profile = await bridge.bluetoothLightingProfile(preferredPeripheralName: parsed.preferredPeripheralName)
            let zoneChoices = await bridge.bluetoothLightingZoneChoices(preferredPeripheralName: parsed.preferredPeripheralName)
            let supportedLEDIDs = try await bridge.bluetoothLightingLEDIDs(preferredPeripheralName: parsed.preferredPeripheralName)
            print("bt profile=\"\(profile?.productName ?? "unknown")\" name=\"\(parsed.preferredPeripheralName ?? "")\"")
            if supportedLEDIDs.isEmpty { print("supported-led-ids: none") } else { print("supported-led-ids=\(hexLEDIDList(supportedLEDIDs))") }
            if let targets = try await bridge.bluetoothLightingTargets(preferredPeripheralName: parsed.preferredPeripheralName) { for target in targets { print(describeBTLightingTarget(target)) } }
            guard let reads = try await bridge.readBluetoothLighting(preferredPeripheralName: parsed.preferredPeripheralName, zoneID: parsed.zoneID) else { throw invalidBTLightingZone(zoneID: parsed.zoneID, choices: zoneChoices) }
            for read in reads { print(describeBTLightingReadResult(read)) }
        case "bt-lighting-read":
            let bridge = ProbeBridge()
            let parsed = try parseBTLightingZoneArgs(commandArgs)
            let zoneChoices = await bridge.bluetoothLightingZoneChoices(preferredPeripheralName: parsed.preferredPeripheralName)
            guard let reads = try await bridge.readBluetoothLighting(preferredPeripheralName: parsed.preferredPeripheralName, zoneID: parsed.zoneID) else { throw invalidBTLightingZone(zoneID: parsed.zoneID, choices: zoneChoices) }
            for read in reads { print(describeBTLightingReadResult(read)) }
        case "bt-lighting-brightness":
            let bridge = ProbeBridge()
            let parsed = try parseBTLightingBrightnessArgs(commandArgs)
            let zoneChoices = await bridge.bluetoothLightingZoneChoices(preferredPeripheralName: parsed.preferredPeripheralName)
            guard let writes = try await bridge.writeBluetoothLightingBrightness(value: parsed.value, preferredPeripheralName: parsed.preferredPeripheralName, zoneID: parsed.zoneID) else { throw invalidBTLightingZone(zoneID: parsed.zoneID, choices: zoneChoices) }
            for write in writes { print(describeBTLightingWriteResult(write, operation: "brightness")) }
            guard writes.allSatisfy(\.succeeded) else { throw ProbeError.protocolError("One or more BT lighting brightness writes failed") }
            guard let reads = try await bridge.readBluetoothLighting(preferredPeripheralName: parsed.preferredPeripheralName, zoneID: parsed.zoneID) else { throw invalidBTLightingZone(zoneID: parsed.zoneID, choices: zoneChoices) }
            for read in reads { print(describeBTLightingReadResult(read)) }
        case "bt-lighting-color":
            let bridge = ProbeBridge()
            let parsed = try parseBTLightingColorArgs(commandArgs)
            let zoneChoices = await bridge.bluetoothLightingZoneChoices(preferredPeripheralName: parsed.preferredPeripheralName)
            guard let writes = try await bridge.writeBluetoothLightingColor(color: parsed.color, preferredPeripheralName: parsed.preferredPeripheralName, zoneID: parsed.zoneID) else { throw invalidBTLightingZone(zoneID: parsed.zoneID, choices: zoneChoices) }
            for write in writes { print(describeBTLightingWriteResult(write, operation: "color")) }
            guard writes.allSatisfy(\.succeeded) else { throw ProbeError.protocolError("One or more BT lighting color writes failed") }
            guard let reads = try await bridge.readBluetoothLighting(preferredPeripheralName: parsed.preferredPeripheralName, zoneID: parsed.zoneID) else { throw invalidBTLightingZone(zoneID: parsed.zoneID, choices: zoneChoices) }
            for read in reads { print(describeBTLightingReadResult(read)) }
        default: return false
        }
        return true
    }

    static func runUSBCommand(_ command: String, commandArgs: [String]) async throws {
        if try await runUSBGeneralCommand(command, commandArgs: commandArgs) { return }
        if try await runUSBProfileCommand(command, commandArgs: commandArgs) { return }
        if try await runUSBLightingCommand(command, commandArgs: commandArgs) { return }
        if try await runUSBInputCommand(command, commandArgs: commandArgs) { return }
        throw ProbeError.usage(usageText)
    }

    private static func runUSBGeneralCommand(_ command: String, commandArgs: [String]) async throws -> Bool {
        switch command {
        case "usb-info":
            let usb = try USBProbeClient(productID: try parseOptionalUSBPID(commandArgs))
            print("usb \(usb.describe())")
        case "usb-battery-read":
            let usb = try USBProbeClient(productID: try parseOptionalUSBPID(commandArgs))
            print("usb \(usb.describe())")
            if let battery = try usb.readBattery() { print("battery charging=\(battery.charging ? "yes" : "no") " + "raw=0x\(String(format: "%02x", battery.rawLevel)) " + "percent=\(battery.percent)") } else { print("battery: unavailable") }
        default: return false
        }
        return true
    }

    private static func runUSBProfileCommand(_ command: String, commandArgs: [String]) async throws -> Bool {
        switch command {
        case "usb-profile-read":
            let parsed = try parseUSBProfileReadArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb-profile-read \(usb.describe()) " + "profiles=\(parsed.profiles.map { String($0) }.joined(separator: ",")) " + "buttonSlots=\(parsed.buttonSlots.map { String($0) }.joined(separator: ",")) " + "includeEffective=\(parsed.includeEffective ? "on" : "off")")
            try printUSBProfileReadSweep(usb: usb, profiles: parsed.profiles, buttonSlots: parsed.buttonSlots, includeEffective: parsed.includeEffective)
        case "usb-profile-active-read":
            let usb = try USBProbeClient(productID: try parseOptionalUSBPID(commandArgs))
            print("usb-profile-active-read \(usb.describe())")
            if let active = try usb.readActiveProfileID() { print("active-profile class=05 cmd=84 value=\(active) \(usbProfileLabel(active))") } else { print("active-profile class=05 cmd=84 read_failed") }
        case "usb-profile-active-set":
            let parsed = try parseUSBProfileActiveSetArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            let before = try usb.readActiveProfileID()
            print("usb-profile-active-set \(usb.describe()) profile=\(parsed.profile) \(usbProfileLabel(parsed.profile))")
            let selected = try usb.writeActiveProfileID(parsed.profile)
            let after = try usb.readActiveProfileID()
            print("active-profile-set command=05:04 " + "accepted=\(selected ? "yes" : "no") " + "before=\(before.map(String.init) ?? "nil") " + "after=\(after.map(String.init) ?? "nil")")
            guard selected else { throw ProbeError.protocolError("USB profile \(parsed.profile) was rejected by active-profile selector 05:04") }
        case "usb-profile-verify-writes":
            let parsed = try parseUSBProfileVerifyWritesArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb-profile-verify-writes \(usb.describe()) profile=\(parsed.profile)")
            try verifyUSBProfileSameValueWrites(usb: usb, profile: parsed.profile)
        case "usb-profile-verify-changed-writes":
            let parsed = try parseUSBProfileVerifyWritesArgs(commandArgs, command: "usb-profile-verify-changed-writes")
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb-profile-verify-changed-writes \(usb.describe()) profile=\(parsed.profile)")
            try verifyUSBProfileChangedValueWrites(usb: usb, profile: parsed.profile)
        case "usb-profile-clone":
            let parsed = try parseUSBProfileCloneArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print(
                "usb-profile-clone \(usb.describe()) " + "source=\(parsed.sourceProfile) \(usbProfileLabel(parsed.sourceProfile)) " + "target=\(parsed.targetProfile) \(usbProfileLabel(parsed.targetProfile)) " + "metadata=\(parsed.metadataMode.rawValue) "
                    + "content=\(parsed.cloneMappedContent ? "on" : "off") " + "buttons=\(parsed.buttonSlots.map(String.init).joined(separator: ","))")
            try cloneUSBProfile(
                USBProfileCloneRequest(
                    usb: usb, sourceProfile: parsed.sourceProfile, targetProfile: parsed.targetProfile, metadataMode: parsed.metadataMode, targetName: parsed.targetName, targetIdentifier: parsed.targetIdentifier, cloneMappedContent: parsed.cloneMappedContent, buttonSlots: parsed.buttonSlots))
        case "usb-profile-verify-metadata-write": throw ProbeError.protocolError("usb-profile-verify-metadata-write is disabled: 05:08 metadata chunks are mapped, but create/assign can disturb profile content and needs a guarded rewrite/readback probe")
        case "usb-profile-delete":
            let parsed = try parseUSBProfileDeleteArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb-profile-delete \(usb.describe()) profile=\(parsed.profile) mode=delete-unassign")
            let deleted = try usb.deleteProfile(profile: parsed.profile)
            print("delete-unassign \(usbProfileLabel(parsed.profile)) command=05:03 status=\(deleted ? "ok" : "read_failed")")
            guard deleted else { throw ProbeError.protocolError("USB profile delete/unassign did not echo the expected command") }
        default: return false
        }
        return true
    }

    private static func runUSBLightingCommand(_ command: String, commandArgs: [String]) async throws -> Bool {
        switch command {
        case "usb-lighting-info":
            let parsed = try parseUSBLightingZoneArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            print("supported-effects=\(usb.supportedLightingEffects().map(\.rawValue).joined(separator: ","))")
            let zones = usb.availableLightingZones()
            if zones.isEmpty {
                print("zones: all -> [0x01]")
            } else {
                for zone in zones {
                    let ledIDs = zone.ledIDs.map { String(format: "0x%02x", $0) }.joined(separator: ",")
                    print("zone id=\(zone.id) label=\"\(zone.label)\" ledIDs=[\(ledIDs)]")
                }
            }
            guard let reads = try usb.readLightingBrightness(zoneID: parsed.zoneID) else { throw invalidUSBLightingZone(zoneID: parsed.zoneID, usb: usb) }
            for read in reads { print(describeUSBLightingReadResult(read)) }
        case "usb-lighting-read":
            let parsed = try parseUSBLightingZoneArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            guard let reads = try usb.readLightingBrightness(zoneID: parsed.zoneID) else { throw invalidUSBLightingZone(zoneID: parsed.zoneID, usb: usb) }
            for read in reads { print(describeUSBLightingReadResult(read)) }
        case "usb-lighting-brightness":
            let parsed = try parseUSBLightingBrightnessArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            guard let writes = try usb.writeLightingBrightness(value: parsed.value, zoneID: parsed.zoneID) else { throw invalidUSBLightingZone(zoneID: parsed.zoneID, usb: usb) }
            for write in writes { print(describeUSBLightingWriteResult(write, operation: "brightness")) }
            guard let reads = try usb.readLightingBrightness(zoneID: parsed.zoneID) else { throw invalidUSBLightingZone(zoneID: parsed.zoneID, usb: usb) }
            for read in reads { print(describeUSBLightingReadResult(read)) }
            guard writes.allSatisfy(\.succeeded) else { throw ProbeError.protocolError("One or more USB lighting brightness writes failed") }
        case "usb-lighting-effect":
            let parsed = try parseUSBLightingEffectArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            let supportedEffects = usb.supportedLightingEffects()
            guard supportedEffects.contains(parsed.effect.kind) else { throw ProbeError.usage("Unsupported --kind '\(parsed.effect.kind.rawValue)' for this device (supported: \(supportedEffects.map(\.rawValue).joined(separator: ",")))") }
            guard let writes = try usb.writeLightingEffect(effect: parsed.effect, zoneID: parsed.zoneID) else { throw invalidUSBLightingZone(zoneID: parsed.zoneID, usb: usb) }
            for write in writes { print(describeUSBLightingWriteResult(write, operation: parsed.effect.kind.rawValue)) }
            guard writes.allSatisfy(\.succeeded) else { throw ProbeError.protocolError("One or more USB lighting effect writes failed") }
        case "usb-lighting-frame":
            let parsed = try parseUSBLightingFrameArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            let result = try usb.writeLightingCustomFrame(storage: parsed.storage, row: parsed.row, startColumn: parsed.startColumn, colors: parsed.colors)
            print(
                "custom-frame storage=0x\(String(format: "%02x", parsed.storage)) " + "row=0x\(String(format: "%02x", parsed.row)) " + "cols=0x\(String(format: "%02x", parsed.startColumn))..0x\(String(format: "%02x", parsed.endColumn)) "
                    + "cells=\(parsed.colors.count) args=[\(hexString(result.args))] " + "status=\(result.succeeded ? "ok" : "failed")")
            guard result.succeeded else { throw ProbeError.protocolError("USB lighting custom-frame write failed") }
        case "usb-lighting-concurrency":
            let parsed = try parseUSBLightingConcurrencyArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe()) concurrency frames=\(parsed.frames) commands=\(parsed.commands) " + "intervalMs=\(parsed.intervalMs) responseDelayUs=\(parsed.responseDelayUs)")
            for mode in parsed.modes {
                let result = await usb.runLightingConcurrencyProbe(frames: parsed.frames, commandLoops: parsed.commands, intervalMs: parsed.intervalMs, responseDelayUs: parsed.responseDelayUs, unlocked: mode == .unlocked)
                print(describeUSBLightingConcurrencyResult(result))
            }
        default: return false
        }
        return true
    }

    private static func runUSBInputCommand(_ command: String, commandArgs: [String]) async throws -> Bool {
        switch command {
        case "usb-input-listen":
            let parsed = try parseUSBInputListenArgs(commandArgs)
            let probe = try USBInputReportProbe(productID: parsed.productID)
            print("usb-input-listen candidates=\(probe.candidateCount) duration=\(String(format: "%.1f", parsed.durationSeconds))s")
            for line in probe.describeCandidates() { print(line) }
            let reportCount = try await probe.capture(duration: parsed.durationSeconds, maxReports: parsed.maxReports) { event in
                let hex = event.report.map { String(format: "%02x", $0) }.joined(separator: " ")
                let passiveNote: String
                if let passive = event.passiveDPI { passiveNote = " passiveDpi=\(passive.dpiX)x\(passive.dpiY)" } else { passiveNote = "" }
                print(String(format: "[+%.3fs] candidate[%d] usage=%@ input=%d feature=%d report[%d]=%@%@", event.elapsedSeconds, event.candidateIndex, event.usageLabel, event.maxInputReportSize, event.maxFeatureReportSize, event.report.count, hex, passiveNote))
            }
            print("usb-input-listen complete reports=\(reportCount)")
        case "usb-input-values":
            let parsed = try parseUSBInputListenArgs(commandArgs)
            let probe = try USBInputValueProbe(productID: parsed.productID)
            print("usb-input-values candidates=\(probe.candidateCount) duration=\(String(format: "%.1f", parsed.durationSeconds))s")
            for line in probe.describeCandidates() { print(line) }
            let eventCount = try await probe.capture(duration: parsed.durationSeconds, maxEvents: parsed.maxReports) { event in
                print(String(format: "[+%.3fs] candidate[%d] deviceUsage=%@ element=%@ reportID=%d value=%d", event.elapsedSeconds, event.candidateIndex, event.deviceUsageLabel, event.elementUsageLabel, event.reportID, event.integerValue))
            }
            print("usb-input-values complete events=\(eventCount)")
        case "usb-button-read":
            let parsed = try parseUSBButtonReadArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            let slot = UInt8(max(0, min(255, parsed.slot)))
            for profile in parsed.profiles {
                if let block = try usb.readButtonFunction(profile: profile, slot: slot, hypershift: parsed.hypershift) {
                    print("profile=\(profile) slot=\(parsed.slot) hypershift=\(parsed.hypershift) \(describeUSBFunctionBlock(block))")
                } else {
                    print("profile=\(profile) slot=\(parsed.slot) hypershift=\(parsed.hypershift) read_failed")
                }
            }
        case "usb-button-set":
            let parsed = try parseUSBButtonSetArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            let wrote = try usb.writeButtonBinding(USBButtonBindingWriteRequest(profiles: parsed.profiles, slot: parsed.slot, kind: parsed.kind, hidKey: parsed.hidKey, turboEnabled: parsed.turboEnabled, turboRate: parsed.turboRate, clutchDPI: parsed.clutchDPI))
            guard wrote else { throw ProbeError.protocolError("USB button write did not return success") }
            let slot = UInt8(max(0, min(255, parsed.slot)))
            for profile in parsed.profiles { if let block = try usb.readButtonFunction(profile: profile, slot: slot, hypershift: 0x00) { print("readback profile=\(profile) slot=\(parsed.slot) \(describeUSBFunctionBlock(block))") } }
        case "usb-button-set-raw":
            let parsed = try parseUSBButtonSetRawArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            let slot = UInt8(max(0, min(255, parsed.slot)))
            var wroteAny = false
            for profile in parsed.profiles where try usb.writeButtonFunction(profile: profile, slot: slot, hypershift: 0x00, functionBlock: parsed.functionBlock) { wroteAny = true }
            guard wroteAny else { throw ProbeError.protocolError("USB raw button write did not return success") }
            for profile in parsed.profiles { if let block = try usb.readButtonFunction(profile: profile, slot: slot, hypershift: 0x00) { print("readback profile=\(profile) slot=\(parsed.slot) \(describeUSBFunctionBlock(block))") } }
        case "usb-raw":
            let parsed = try parseUSBRawArgs(commandArgs)
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            let response = try usb.rawCommand(classID: parsed.classID, cmdID: parsed.cmdID, size: parsed.size, args: parsed.args, responseAttempts: parsed.responseAttempts, responseDelayUs: parsed.responseDelayUs)
            if let response {
                let hex = response.map { String(format: "%02x", $0) }.joined(separator: " ")
                print("response[\(response.count)]: \(hex)")
            } else {
                print("response: nil")
            }
        default: return false
        }
        return true
    }
}
