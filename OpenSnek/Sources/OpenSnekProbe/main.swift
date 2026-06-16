import Foundation
import OpenSnekCore
import OpenSnekProtocols

enum OpenSnekProbe {
    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            throw ProbeError.usage(usageText)
        }

        switch command {
        case "dpi-read":
            let bridge = ProbeBridge()
            let snapshot = try await bridge.readDpi()
            print("active=\(snapshot.active + 1) count=\(snapshot.count) values=\(snapshot.values)")
        case "dpi-set":
            let bridge = ProbeBridge()
            let parsed = try parseSetArgs(Array(args.dropFirst()))
            let snapshot = try await bridge.setDpi(
                active: parsed.active,
                values: parsed.values,
                verifyRetries: parsed.verifyRetries,
                verifyDelayMs: parsed.verifyDelayMs
            )
            print("applied active=\(snapshot.active + 1) values=\(snapshot.values)")
        case "dpi-cycle":
            let bridge = ProbeBridge()
            let parsed = try parseCycleArgs(Array(args.dropFirst()))
            for i in 0..<parsed.loops {
                let values = parsed.sequence[i % parsed.sequence.count]
                let snapshot = try await bridge.setDpi(
                    active: parsed.active,
                    values: values,
                    verifyRetries: parsed.verifyRetries,
                    verifyDelayMs: parsed.verifyDelayMs
                )
                print("loop \(i + 1): active=\(snapshot.active + 1) values=\(snapshot.values)")
                if parsed.sleepMs > 0 {
                    try await Task.sleep(nanoseconds: UInt64(parsed.sleepMs) * 1_000_000)
                }
            }
        case "bt-info":
            let bridge = ProbeBridge()
            let summaries = await bridge.connectedPeripherals() ?? []
            if summaries.isEmpty {
                print("bt connected-peripherals: none")
            } else {
                for summary in summaries {
                    print("bt peripheral name=\"\(summary.name ?? "")\" id=\(summary.identifier.uuidString)")
                }
            }
        case "bt-raw-read":
            let bridge = ProbeBridge()
            let parsed = try parseBTRawReadArgs(Array(args.dropFirst()))
            let result = try await bridge.rawRead(
                key: parsed.key,
                timeout: parsed.timeoutSeconds,
                preferredPeripheralName: parsed.preferredPeripheralName
            )
            print("bt-raw-read req=0x\(String(format: "%02x", result.req)) key=\(hexString(parsed.key)) name=\"\(parsed.preferredPeripheralName ?? "")\"")
            print(describeBTNotifyFrames(result.notifies))
            if let payload = result.payload {
                print("payload[\(payload.count)]: \(hexString(Array(payload)))")
                if let decoded = decodeBTButtonReadFunctionBlock(
                    key: parsed.key,
                    payload: payload,
                    notifies: result.notifies
                ) {
                    print("decoded-button-function[\(decoded.count)]: \(hexString(decoded))")
                }
            } else {
                print("payload: nil")
            }
        case "bt-raw-write":
            let bridge = ProbeBridge()
            let parsed = try parseBTRawWriteArgs(Array(args.dropFirst()))
            let result = try await bridge.rawWrite(
                key: parsed.key,
                payload: Data(parsed.payload),
                timeout: parsed.timeoutSeconds,
                preferredPeripheralName: parsed.preferredPeripheralName
            )
            print("bt-raw-write req=0x\(String(format: "%02x", result.req)) key=\(hexString(parsed.key)) payload=\(hexString(parsed.payload)) name=\"\(parsed.preferredPeripheralName ?? "")\"")
            print(describeBTNotifyFrames(result.notifies))
            if let ack = result.ack {
                print("ack status=0x\(String(format: "%02x", ack.status)) payloadLength=\(ack.payloadLength)")
            } else {
                print("ack: nil")
            }
        case "bt-profile-read":
            let bridge = ProbeBridge()
            let parsed = try parseBTProfileReadArgs(Array(args.dropFirst()))
            print(
                "bt-profile-read name=\"\(parsed.preferredPeripheralName ?? "")\" " +
                "targets=\(parsed.targets.map { String($0) }.joined(separator: ",")) " +
                "buttonSlots=\(parsed.buttonSlots.map { String($0) }.joined(separator: ","))"
            )
            try await printBTProfileReadSweep(
                bridge: bridge,
                preferredPeripheralName: parsed.preferredPeripheralName,
                timeoutSeconds: parsed.timeoutSeconds,
                targets: parsed.targets,
                buttonSlots: parsed.buttonSlots,
                includeLiveButtons: parsed.includeLiveButtons
            )
        case "bt-profile-active-set":
            let bridge = ProbeBridge()
            let parsed = try parseBTProfileActiveSetArgs(Array(args.dropFirst()))
            let readKey = BLEVendorProtocol.Key.profileActiveTargetGet().bytes
            let before = try await bridge.rawRead(
                key: readKey,
                timeout: parsed.timeoutSeconds,
                preferredPeripheralName: parsed.preferredPeripheralName
            )
            let write = try await bridge.rawWrite(
                key: BLEVendorProtocol.Key.profileActiveTargetSet().bytes,
                payload: BLEVendorProtocol.Key.profileActiveTargetSetPayload(target: parsed.target),
                timeout: parsed.timeoutSeconds,
                preferredPeripheralName: parsed.preferredPeripheralName
            )
            let after = try await bridge.rawRead(
                key: readKey,
                timeout: parsed.timeoutSeconds,
                preferredPeripheralName: parsed.preferredPeripheralName
            )
            let beforeTarget = before.payload?.first
            let afterTarget = after.payload?.first
            print(
                "bt-profile-active-set target=\(parsed.target) \(btProfileTargetLabel(parsed.target)) " +
                "before=\(beforeTarget.map(String.init) ?? "nil") " +
                "ack=\(describeBTAckStatus(write.ack)) " +
                "after=\(afterTarget.map(String.init) ?? "nil")"
            )
            guard write.ack?.status == 0x02, afterTarget == parsed.target else {
                throw ProbeError.protocolError("BT active-target selector did not select target \(parsed.target)")
            }
        case "bt-profile-create":
            let bridge = ProbeBridge()
            let parsed = try parseBTProfileCreateArgs(Array(args.dropFirst()))
            print(
                "bt-profile-create \(btProfileTargetLabel(parsed.target)) " +
                "profileName=\"\(parsed.profileName)\" guid=\(parsed.guid.uuidString.lowercased()) " +
                "dpi=\(parsed.values) active=\(parsed.active + 1) brightness=\(parsed.brightness)"
            )
            try await createBTProfileTarget(
                bridge: bridge,
                preferredPeripheralName: parsed.preferredPeripheralName,
                timeoutSeconds: parsed.timeoutSeconds,
                target: parsed.target,
                guid: parsed.guid,
                profileName: parsed.profileName,
                owner: parsed.owner,
                values: parsed.values,
                active: parsed.active,
                brightness: parsed.brightness
            )
        case "bt-profile-button-read":
            let bridge = ProbeBridge()
            let parsed = try parseBTProfileButtonReadArgs(Array(args.dropFirst()))
            let key = BLEVendorProtocol.Key.buttonBindGet(target: parsed.target, slot: parsed.buttonSlot).bytes
            let result = try await bridge.rawRead(
                key: key,
                timeout: parsed.timeoutSeconds,
                preferredPeripheralName: parsed.preferredPeripheralName
            )
            print(
                "bt-profile-button-read \(btProfileTargetLabel(parsed.target)) " +
                "slot=\(parsed.buttonSlot) key=\(hexString(key)) name=\"\(parsed.preferredPeripheralName ?? "")\""
            )
            print(describeBTNotifyFrames(result.notifies))
            print(describeBTProfileButtonRead(key: key, payload: result.payload, notifies: result.notifies))
        case "bt-profile-button-set":
            let bridge = ProbeBridge()
            let parsed = try parseBTProfileButtonSetArgs(Array(args.dropFirst()))
            let storedKey = BLEVendorProtocol.Key.buttonBindSet(target: parsed.target, slot: parsed.buttonSlot).bytes
            let storedPayload = parsed.payload
            let storedResult = try await bridge.rawWrite(
                key: storedKey,
                payload: Data(storedPayload),
                timeout: parsed.timeoutSeconds,
                preferredPeripheralName: parsed.preferredPeripheralName
            )
            print(
                "bt-profile-button-set \(btProfileTargetLabel(parsed.target)) " +
                "slot=\(parsed.buttonSlot) key=\(hexString(storedKey)) payload=\(hexString(storedPayload)) " +
                "status=\(describeBTAckStatus(storedResult.ack))"
            )
            if parsed.projectLive {
                let livePayload = Array(BLEVendorProtocol.retargetButtonPayload(
                    Data(storedPayload),
                    target: 0x01,
                    slot: parsed.buttonSlot
                ))
                let liveKey = BLEVendorProtocol.Key.buttonBindSet(target: 0x01, slot: parsed.buttonSlot).bytes
                let liveResult = try await bridge.rawWrite(
                    key: liveKey,
                    payload: Data(livePayload),
                    timeout: parsed.timeoutSeconds,
                    preferredPeripheralName: parsed.preferredPeripheralName
                )
                print(
                    "bt-profile-button-set live-projection slot=\(parsed.buttonSlot) " +
                    "key=\(hexString(liveKey)) payload=\(hexString(livePayload)) status=\(describeBTAckStatus(liveResult.ack))"
                )
            }
            let readbackTargets = parsed.projectLive ? [parsed.target, 0x01] : [parsed.target]
            for target in readbackTargets {
                let readKey = BLEVendorProtocol.Key.buttonBindGet(target: target, slot: parsed.buttonSlot).bytes
                let readback = try await bridge.rawRead(
                    key: readKey,
                    timeout: parsed.timeoutSeconds,
                    preferredPeripheralName: parsed.preferredPeripheralName
                )
                print("readback \(btProfileTargetLabel(target)) slot=\(parsed.buttonSlot)")
                print(describeBTProfileButtonRead(key: readKey, payload: readback.payload, notifies: readback.notifies))
            }
        case "bt-profile-hid-watch", "bt-profile-cycle-watch":
            let parsed = try parseBTProfileHIDWatchArgs(Array(args.dropFirst()))
            let probe = try BTProfileHIDReportProbe(
                productID: parsed.productID,
                preferredPeripheralName: parsed.preferredPeripheralName
            )
            print(
                "bt-profile-hid-watch candidates=\(probe.candidateCount) " +
                "duration=\(String(format: "%.1f", parsed.durationSeconds))s " +
                "maxReports=\(parsed.maxReports.map(String.init) ?? "unlimited")"
            )
            for line in probe.describeCandidates() {
                print(line)
            }
            let reportCount = try await probe.capture(
                duration: parsed.durationSeconds,
                maxReports: parsed.maxReports
            ) { event in
                let hex = event.report.map { String(format: "%02x", $0) }.joined(separator: " ")
                print(
                    String(
                        format: "[+%.3fs] candidate[%d] usage=%@ input=%d feature=%d class=%@ report[%d]=%@",
                        event.elapsedSeconds,
                        event.candidateIndex,
                        event.usageLabel,
                        event.maxInputReportSize,
                        event.maxFeatureReportSize,
                        event.classification.label,
                        event.report.count,
                        hex
                    )
                )
            }
            print("bt-profile-hid-watch complete reports=\(reportCount)")
        case "bt-profile-watch":
            let bridge = ProbeBridge()
            let parsed = try parseBTProfileWatchArgs(Array(args.dropFirst()))
            print(
                "bt-profile-watch name=\"\(parsed.preferredPeripheralName ?? "")\" " +
                "slot=\(parsed.buttonSlot) polls=\(parsed.samples) pollMs=\(parsed.pollMs)"
            )
            print("note: this fingerprints the live projected Bluetooth layer, not the persistent stored slots.")

            var previous: BTProfileWatchSnapshot?
            var seenSignatures: [String: Int] = [:]

            for pollIndex in 0..<parsed.samples {
                let snapshot = try await readBTProfileWatchSnapshot(
                    bridge: bridge,
                    preferredPeripheralName: parsed.preferredPeripheralName,
                    timeoutSeconds: parsed.timeoutSeconds,
                    buttonSlot: parsed.buttonSlot
                )
                let signatureID = seenSignatures[snapshot.signature] ?? {
                    let next = seenSignatures.count + 1
                    seenSignatures[snapshot.signature] = next
                    return next
                }()

                let prefix: String
                if let previous, previous.signature != snapshot.signature {
                    prefix = "CHANGE"
                } else if previous == nil {
                    prefix = "BASE"
                } else {
                    prefix = "SAME"
                }

                print(
                    "[poll \(pollIndex + 1)/\(parsed.samples)] \(prefix) " +
                    "signature#\(signatureID) \(snapshot.summary)"
                )

                if let previous, previous.signature != snapshot.signature {
                    print("  from: \(previous.summary)")
                    print("  to:   \(snapshot.summary)")
                }

                previous = snapshot
                if pollIndex + 1 < parsed.samples, parsed.pollMs > 0 {
                    try await Task.sleep(nanoseconds: UInt64(parsed.pollMs) * 1_000_000)
                }
            }
        case "bt-lighting-info":
            let bridge = ProbeBridge()
            let parsed = try parseBTLightingZoneArgs(Array(args.dropFirst()))
            let profile = await bridge.bluetoothLightingProfile(preferredPeripheralName: parsed.preferredPeripheralName)
            let zoneChoices = await bridge.bluetoothLightingZoneChoices(preferredPeripheralName: parsed.preferredPeripheralName)
            let supportedLEDIDs = try await bridge.bluetoothLightingLEDIDs(preferredPeripheralName: parsed.preferredPeripheralName)
            print("bt profile=\"\(profile?.productName ?? "unknown")\" name=\"\(parsed.preferredPeripheralName ?? "")\"")
            if supportedLEDIDs.isEmpty {
                print("supported-led-ids: none")
            } else {
                print("supported-led-ids=\(hexLEDIDList(supportedLEDIDs))")
            }
            if let targets = try await bridge.bluetoothLightingTargets(preferredPeripheralName: parsed.preferredPeripheralName) {
                for target in targets {
                    print(describeBTLightingTarget(target))
                }
            }
            guard let reads = try await bridge.readBluetoothLighting(
                preferredPeripheralName: parsed.preferredPeripheralName,
                zoneID: parsed.zoneID
            ) else {
                throw invalidBTLightingZone(zoneID: parsed.zoneID, choices: zoneChoices)
            }
            for read in reads {
                print(describeBTLightingReadResult(read))
            }
        case "bt-lighting-read":
            let bridge = ProbeBridge()
            let parsed = try parseBTLightingZoneArgs(Array(args.dropFirst()))
            let zoneChoices = await bridge.bluetoothLightingZoneChoices(preferredPeripheralName: parsed.preferredPeripheralName)
            guard let reads = try await bridge.readBluetoothLighting(
                preferredPeripheralName: parsed.preferredPeripheralName,
                zoneID: parsed.zoneID
            ) else {
                throw invalidBTLightingZone(zoneID: parsed.zoneID, choices: zoneChoices)
            }
            for read in reads {
                print(describeBTLightingReadResult(read))
            }
        case "bt-lighting-brightness":
            let bridge = ProbeBridge()
            let parsed = try parseBTLightingBrightnessArgs(Array(args.dropFirst()))
            let zoneChoices = await bridge.bluetoothLightingZoneChoices(preferredPeripheralName: parsed.preferredPeripheralName)
            guard let writes = try await bridge.writeBluetoothLightingBrightness(
                value: parsed.value,
                preferredPeripheralName: parsed.preferredPeripheralName,
                zoneID: parsed.zoneID
            ) else {
                throw invalidBTLightingZone(zoneID: parsed.zoneID, choices: zoneChoices)
            }
            for write in writes {
                print(describeBTLightingWriteResult(write, operation: "brightness"))
            }
            guard writes.allSatisfy(\.succeeded) else {
                throw ProbeError.protocolError("One or more BT lighting brightness writes failed")
            }
            guard let reads = try await bridge.readBluetoothLighting(
                preferredPeripheralName: parsed.preferredPeripheralName,
                zoneID: parsed.zoneID
            ) else {
                throw invalidBTLightingZone(zoneID: parsed.zoneID, choices: zoneChoices)
            }
            for read in reads {
                print(describeBTLightingReadResult(read))
            }
        case "bt-lighting-color":
            let bridge = ProbeBridge()
            let parsed = try parseBTLightingColorArgs(Array(args.dropFirst()))
            let zoneChoices = await bridge.bluetoothLightingZoneChoices(preferredPeripheralName: parsed.preferredPeripheralName)
            guard let writes = try await bridge.writeBluetoothLightingColor(
                color: parsed.color,
                preferredPeripheralName: parsed.preferredPeripheralName,
                zoneID: parsed.zoneID
            ) else {
                throw invalidBTLightingZone(zoneID: parsed.zoneID, choices: zoneChoices)
            }
            for write in writes {
                print(describeBTLightingWriteResult(write, operation: "color"))
            }
            guard writes.allSatisfy(\.succeeded) else {
                throw ProbeError.protocolError("One or more BT lighting color writes failed")
            }
            guard let reads = try await bridge.readBluetoothLighting(
                preferredPeripheralName: parsed.preferredPeripheralName,
                zoneID: parsed.zoneID
            ) else {
                throw invalidBTLightingZone(zoneID: parsed.zoneID, choices: zoneChoices)
            }
            for read in reads {
                print(describeBTLightingReadResult(read))
            }
        case "usb-info":
            let usb = try USBProbeClient(productID: try parseOptionalUSBPID(Array(args.dropFirst())))
            print("usb \(usb.describe())")
        case "usb-profile-read":
            let parsed = try parseUSBProfileReadArgs(Array(args.dropFirst()))
            let usb = try USBProbeClient(productID: parsed.productID)
            print(
                "usb-profile-read \(usb.describe()) " +
                "profiles=\(parsed.profiles.map { String($0) }.joined(separator: ",")) " +
                "buttonSlots=\(parsed.buttonSlots.map { String($0) }.joined(separator: ",")) " +
                "includeEffective=\(parsed.includeEffective ? "on" : "off")"
            )
            try printUSBProfileReadSweep(
                usb: usb,
                profiles: parsed.profiles,
                buttonSlots: parsed.buttonSlots,
                includeEffective: parsed.includeEffective
            )
        case "usb-profile-active-read":
            let usb = try USBProbeClient(productID: try parseOptionalUSBPID(Array(args.dropFirst())))
            print("usb-profile-active-read \(usb.describe())")
            if let active = try usb.readActiveProfileID() {
                print("active-profile class=05 cmd=84 value=\(active) \(usbProfileLabel(active))")
            } else {
                print("active-profile class=05 cmd=84 read_failed")
            }
        case "usb-profile-active-set":
            let parsed = try parseUSBProfileActiveSetArgs(Array(args.dropFirst()))
            let usb = try USBProbeClient(productID: parsed.productID)
            let before = try usb.readActiveProfileID()
            print("usb-profile-active-set \(usb.describe()) profile=\(parsed.profile) \(usbProfileLabel(parsed.profile))")
            let selected = try usb.writeActiveProfileID(parsed.profile)
            let after = try usb.readActiveProfileID()
            print(
                "active-profile-set command=05:04 " +
                "accepted=\(selected ? "yes" : "no") " +
                "before=\(before.map(String.init) ?? "nil") " +
                "after=\(after.map(String.init) ?? "nil")"
            )
            guard selected else {
                throw ProbeError.protocolError("USB profile \(parsed.profile) was rejected by active-profile selector 05:04")
            }
        case "usb-profile-verify-writes":
            let parsed = try parseUSBProfileVerifyWritesArgs(Array(args.dropFirst()))
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb-profile-verify-writes \(usb.describe()) profile=\(parsed.profile)")
            try verifyUSBProfileSameValueWrites(usb: usb, profile: parsed.profile)
        case "usb-profile-verify-changed-writes":
            let parsed = try parseUSBProfileVerifyWritesArgs(Array(args.dropFirst()), command: "usb-profile-verify-changed-writes")
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb-profile-verify-changed-writes \(usb.describe()) profile=\(parsed.profile)")
            try verifyUSBProfileChangedValueWrites(usb: usb, profile: parsed.profile)
        case "usb-profile-verify-metadata-write":
            throw ProbeError.protocolError("usb-profile-verify-metadata-write is disabled: 05:08 behaves like an unsafe bulk profile write without a mapped full-profile blob")
        case "usb-profile-delete":
            let parsed = try parseUSBProfileDeleteArgs(Array(args.dropFirst()))
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb-profile-delete \(usb.describe()) profile=\(parsed.profile) mode=delete-unassign")
            let deleted = try usb.deleteProfile(profile: parsed.profile)
            print("delete-unassign \(usbProfileLabel(parsed.profile)) command=05:03 status=\(deleted ? "ok" : "read_failed")")
            guard deleted else {
                throw ProbeError.protocolError("USB profile delete/unassign did not echo the expected command")
            }
        case "usb-battery-read":
            let usb = try USBProbeClient(productID: try parseOptionalUSBPID(Array(args.dropFirst())))
            print("usb \(usb.describe())")
            if let battery = try usb.readBattery() {
                print(
                    "battery charging=\(battery.charging ? "yes" : "no") " +
                    "raw=0x\(String(format: "%02x", battery.rawLevel)) " +
                    "percent=\(battery.percent)"
                )
            } else {
                print("battery: unavailable")
            }
        case "usb-lighting-info":
            let parsed = try parseUSBLightingZoneArgs(Array(args.dropFirst()))
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
            guard let reads = try usb.readLightingBrightness(zoneID: parsed.zoneID) else {
                throw invalidUSBLightingZone(zoneID: parsed.zoneID, usb: usb)
            }
            for read in reads {
                print(describeUSBLightingReadResult(read))
            }
        case "usb-lighting-read":
            let parsed = try parseUSBLightingZoneArgs(Array(args.dropFirst()))
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            guard let reads = try usb.readLightingBrightness(zoneID: parsed.zoneID) else {
                throw invalidUSBLightingZone(zoneID: parsed.zoneID, usb: usb)
            }
            for read in reads {
                print(describeUSBLightingReadResult(read))
            }
        case "usb-lighting-brightness":
            let parsed = try parseUSBLightingBrightnessArgs(Array(args.dropFirst()))
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            guard let writes = try usb.writeLightingBrightness(value: parsed.value, zoneID: parsed.zoneID) else {
                throw invalidUSBLightingZone(zoneID: parsed.zoneID, usb: usb)
            }
            for write in writes {
                print(describeUSBLightingWriteResult(write, operation: "brightness"))
            }
            guard let reads = try usb.readLightingBrightness(zoneID: parsed.zoneID) else {
                throw invalidUSBLightingZone(zoneID: parsed.zoneID, usb: usb)
            }
            for read in reads {
                print(describeUSBLightingReadResult(read))
            }
            guard writes.allSatisfy(\.succeeded) else {
                throw ProbeError.protocolError("One or more USB lighting brightness writes failed")
            }
        case "usb-lighting-effect":
            let parsed = try parseUSBLightingEffectArgs(Array(args.dropFirst()))
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            let supportedEffects = usb.supportedLightingEffects()
            guard supportedEffects.contains(parsed.effect.kind) else {
                throw ProbeError.usage(
                    "Unsupported --kind '\(parsed.effect.kind.rawValue)' for this device (supported: \(supportedEffects.map(\.rawValue).joined(separator: ",")))"
                )
            }
            guard let writes = try usb.writeLightingEffect(effect: parsed.effect, zoneID: parsed.zoneID) else {
                throw invalidUSBLightingZone(zoneID: parsed.zoneID, usb: usb)
            }
            for write in writes {
                print(describeUSBLightingWriteResult(write, operation: parsed.effect.kind.rawValue))
            }
            guard writes.allSatisfy(\.succeeded) else {
                throw ProbeError.protocolError("One or more USB lighting effect writes failed")
            }
        case "usb-input-listen":
            let parsed = try parseUSBInputListenArgs(Array(args.dropFirst()))
            let probe = try USBInputReportProbe(productID: parsed.productID)
            print("usb-input-listen candidates=\(probe.candidateCount) duration=\(String(format: "%.1f", parsed.durationSeconds))s")
            for line in probe.describeCandidates() {
                print(line)
            }
            let reportCount = try await probe.capture(
                duration: parsed.durationSeconds,
                maxReports: parsed.maxReports
            ) { event in
                let hex = event.report.map { String(format: "%02x", $0) }.joined(separator: " ")
                let passiveNote: String
                if let passive = event.passiveDPI {
                    passiveNote = " passiveDpi=\(passive.dpiX)x\(passive.dpiY)"
                } else {
                    passiveNote = ""
                }
                print(
                    String(
                        format: "[+%.3fs] candidate[%d] usage=%@ input=%d feature=%d report[%d]=%@%@",
                        event.elapsedSeconds,
                        event.candidateIndex,
                        event.usageLabel,
                        event.maxInputReportSize,
                        event.maxFeatureReportSize,
                        event.report.count,
                        hex,
                        passiveNote
                    )
                )
            }
            print("usb-input-listen complete reports=\(reportCount)")
        case "usb-input-values":
            let parsed = try parseUSBInputListenArgs(Array(args.dropFirst()))
            let probe = try USBInputValueProbe(productID: parsed.productID)
            print("usb-input-values candidates=\(probe.candidateCount) duration=\(String(format: "%.1f", parsed.durationSeconds))s")
            for line in probe.describeCandidates() {
                print(line)
            }
            let eventCount = try await probe.capture(
                duration: parsed.durationSeconds,
                maxEvents: parsed.maxReports
            ) { event in
                print(
                    String(
                        format: "[+%.3fs] candidate[%d] deviceUsage=%@ element=%@ reportID=%d value=%d",
                        event.elapsedSeconds,
                        event.candidateIndex,
                        event.deviceUsageLabel,
                        event.elementUsageLabel,
                        event.reportID,
                        event.integerValue
                    )
                )
            }
            print("usb-input-values complete events=\(eventCount)")
        case "usb-button-read":
            let parsed = try parseUSBButtonReadArgs(Array(args.dropFirst()))
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
            let parsed = try parseUSBButtonSetArgs(Array(args.dropFirst()))
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            let wrote = try usb.writeButtonBinding(
                profiles: parsed.profiles,
                slot: parsed.slot,
                kind: parsed.kind,
                hidKey: parsed.hidKey,
                turboEnabled: parsed.turboEnabled,
                turboRate: parsed.turboRate,
                clutchDPI: parsed.clutchDPI
            )
            guard wrote else {
                throw ProbeError.protocolError("USB button write did not return success")
            }
            let slot = UInt8(max(0, min(255, parsed.slot)))
            for profile in parsed.profiles {
                if let block = try usb.readButtonFunction(profile: profile, slot: slot, hypershift: 0x00) {
                    print("readback profile=\(profile) slot=\(parsed.slot) \(describeUSBFunctionBlock(block))")
                }
            }
        case "usb-button-set-raw":
            let parsed = try parseUSBButtonSetRawArgs(Array(args.dropFirst()))
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            let slot = UInt8(max(0, min(255, parsed.slot)))
            var wroteAny = false
            for profile in parsed.profiles {
                if try usb.writeButtonFunction(profile: profile, slot: slot, hypershift: 0x00, functionBlock: parsed.functionBlock) {
                    wroteAny = true
                }
            }
            guard wroteAny else {
                throw ProbeError.protocolError("USB raw button write did not return success")
            }
            for profile in parsed.profiles {
                if let block = try usb.readButtonFunction(profile: profile, slot: slot, hypershift: 0x00) {
                    print("readback profile=\(profile) slot=\(parsed.slot) \(describeUSBFunctionBlock(block))")
                }
            }
        case "usb-raw":
            let parsed = try parseUSBRawArgs(Array(args.dropFirst()))
            let usb = try USBProbeClient(productID: parsed.productID)
            print("usb \(usb.describe())")
            let response = try usb.rawCommand(
                classID: parsed.classID,
                cmdID: parsed.cmdID,
                size: parsed.size,
                args: parsed.args,
                allowTxnRescan: !parsed.noTxnRescan,
                responseAttempts: parsed.responseAttempts,
                responseDelayUs: parsed.responseDelayUs
            )
            if let response {
                let hex = response.map { String(format: "%02x", $0) }.joined(separator: " ")
                print("response[\(response.count)]: \(hex)")
            } else {
                print("response: nil")
            }
        default:
            throw ProbeError.usage(usageText)
        }
    }

    private static var usageText: String {
        """
        Usage:
          OpenSnekProbe dpi-read
          OpenSnekProbe dpi-set --values 1600,6400 [--active 1] [--verify-retries 6] [--verify-delay-ms 120]
          OpenSnekProbe dpi-cycle --sequence 800,6400;1600,6400 --loops 10 [--active 1] [--sleep-ms 120]
          OpenSnekProbe bt-info
          OpenSnekProbe bt-raw-read --key 10840000 [--name "BSK V3 PRO"] [--timeout-ms 600]
          OpenSnekProbe bt-raw-write --key 10040000 --payload 0400000000ff4010 [--name "BSK V3 PRO"] [--timeout-ms 900]
          OpenSnekProbe bt-profile-read [--stored-slots 1,2,3,4] [--button-slots 5,106] [--include-live-buttons on|off] [--name "BSK V3 PRO"]
          OpenSnekProbe bt-profile-active-set --target 3 --yes [--name "BSK V3 PRO"]
          OpenSnekProbe bt-profile-create --stored-slot 1 --profile-name OPENSNEK_MAC_SLOT_1 --yes [--name "BSK V3 PRO"]
          OpenSnekProbe bt-profile-button-read --stored-slot 1 --button-slot 5 [--name "BSK V3 PRO"]
          OpenSnekProbe bt-profile-button-set --stored-slot 1 --button-slot 5 [--kind keyboard_simple] [--hid-key 0x09] [--project-live on|off] --yes [--name "BSK V3 PRO"]
          OpenSnekProbe bt-profile-hid-watch [--pid 0x00ac] [--name "BSK V3 PRO"] [--duration 20] [--max-reports 0]
          OpenSnekProbe bt-profile-watch [--name "BSK V3 PRO"] [--slot 4] [--poll-ms 1000] [--samples 20] [--timeout-ms 900]
          OpenSnekProbe bt-lighting-info [--zone all|scroll_wheel|logo|underglow] [--name "BSK V3 PRO"]
          OpenSnekProbe bt-lighting-read [--zone all|scroll_wheel|logo|underglow] [--name "BSK V3 PRO"]
          OpenSnekProbe bt-lighting-brightness --value 128 [--zone all|scroll_wheel|logo|underglow] [--name "BSK V3 PRO"]
          OpenSnekProbe bt-lighting-color --color ff6600 [--zone all|scroll_wheel|logo|underglow] [--name "BSK V3 PRO"]
          OpenSnekProbe usb-info [--pid 0x00ab]
          OpenSnekProbe usb-battery-read [--pid 0x00ab]
          OpenSnekProbe usb-lighting-info [--zone all|scroll_wheel|logo|underglow] [--pid 0x00ab]
          OpenSnekProbe usb-lighting-read [--zone all|scroll_wheel|logo|underglow] [--pid 0x00ab]
          OpenSnekProbe usb-lighting-brightness --value 128 [--zone all|scroll_wheel|logo|underglow] [--pid 0x00ab]
          OpenSnekProbe usb-lighting-effect --kind static [--color 00ff00] [--secondary ff00ff] [--direction left|right] [--speed 2] [--zone all|scroll_wheel|logo|underglow] [--pid 0x00ab]
          OpenSnekProbe usb-profile-read [--profiles 2,3,4,5] [--button-slots 5,106] [--include-effective on|off] [--pid 0x00ab]
          OpenSnekProbe usb-profile-active-read [--pid 0x00ab]
          OpenSnekProbe usb-profile-active-set --profile 3 --yes [--pid 0x00ab]
          OpenSnekProbe usb-profile-verify-writes --profile 5 --yes [--pid 0x00ab]
          OpenSnekProbe usb-profile-verify-changed-writes --profile 5 --yes [--pid 0x00ab]
          OpenSnekProbe usb-profile-verify-metadata-write [disabled: unsafe 05:08 bulk profile write]
          OpenSnekProbe usb-profile-delete --profile 2 --yes [--pid 0x00ab]
          OpenSnekProbe usb-input-listen [--pid 0x00ab] [--duration 15] [--max-reports 0]
          OpenSnekProbe usb-input-values [--pid 0x00ab] [--duration 15] [--max-reports 0]
          OpenSnekProbe usb-button-read --slot 4 [--profile default|direct|both] [--pid 0x00ab]
          OpenSnekProbe usb-button-set --slot 4 --kind right_click [--profile both] [--hid-key 4] [--turbo on|off] [--turbo-rate 142] [--clutch-dpi 400] [--pid 0x00ab]
          OpenSnekProbe usb-button-set-raw --slot 4 --hex 01010200000000 [--profile default|direct|both] [--pid 0x00ab]
          OpenSnekProbe usb-raw --class 0x02 --cmd 0x8C --size 0x0A [--args 01,04,00,00,00,00,00,00,00,00] [--pid 0x00ab]

        USB button kinds:
          default dpi_cycle dpi_clutch left_click right_click middle_click scroll_up scroll_down mouse_back mouse_forward keyboard_simple clear_layer

        USB lighting kinds:
          off static spectrum wave reactive pulse_random pulse_single pulse_dual
        """
    }

    private static func parseSetArgs(_ args: [String]) throws -> (values: [Int], active: Int, verifyRetries: Int, verifyDelayMs: Int) {
        let flags = parseFlags(args)
        guard let valuesRaw = flags["--values"] else {
            throw ProbeError.usage("Missing --values\n\(usageText)")
        }
        let values = try parseValues(valuesRaw)
        let active = max(0, (Int(flags["--active"] ?? "1") ?? 1) - 1)
        let verifyRetries = Int(flags["--verify-retries"] ?? "6") ?? 6
        let verifyDelayMs = Int(flags["--verify-delay-ms"] ?? "120") ?? 120
        return (values, active, verifyRetries, verifyDelayMs)
    }

    private static func parseCycleArgs(_ args: [String]) throws -> (sequence: [[Int]], loops: Int, active: Int, sleepMs: Int, verifyRetries: Int, verifyDelayMs: Int) {
        let flags = parseFlags(args)
        guard let raw = flags["--sequence"] else {
            throw ProbeError.usage("Missing --sequence\n\(usageText)")
        }
        let sequence = try raw.split(separator: ";").map { try parseValues(String($0)) }
        guard !sequence.isEmpty else { throw ProbeError.usage("Empty --sequence") }
        let loops = max(1, Int(flags["--loops"] ?? "10") ?? 10)
        let active = max(0, (Int(flags["--active"] ?? "1") ?? 1) - 1)
        let sleepMs = max(0, Int(flags["--sleep-ms"] ?? "120") ?? 120)
        let verifyRetries = Int(flags["--verify-retries"] ?? "6") ?? 6
        let verifyDelayMs = Int(flags["--verify-delay-ms"] ?? "120") ?? 120
        return (sequence, loops, active, sleepMs, verifyRetries, verifyDelayMs)
    }

    private static func parseUSBButtonReadArgs(_ args: [String]) throws -> (slot: Int, profiles: [UInt8], hypershift: UInt8, productID: Int?) {
        let flags = parseFlags(args)
        guard let slotRaw = flags["--slot"], let slot = Int(slotRaw) else {
            throw ProbeError.usage("Missing --slot\n\(usageText)")
        }
        let profiles = try parseUSBProfiles(flags["--profile"], defaultProfiles: [0x01])
        let hypershift = UInt8(max(0, min(1, Int(flags["--hypershift"] ?? "0") ?? 0)))
        return (slot, profiles, hypershift, try parseOptionalUSBPID(args))
    }

    private static func parseUSBButtonSetArgs(_ args: [String]) throws -> (slot: Int, kind: String, hidKey: Int, turboEnabled: Bool, turboRate: Int, clutchDPI: Int?, profiles: [UInt8], productID: Int?) {
        let flags = parseFlags(args)
        guard let slotRaw = flags["--slot"], let slot = Int(slotRaw) else {
            throw ProbeError.usage("Missing --slot\n\(usageText)")
        }
        guard let kindRaw = flags["--kind"]?.lowercased() else {
            throw ProbeError.usage("Missing --kind\n\(usageText)")
        }
        let validKinds: Set<String> = [
            "default", "dpi_cycle", "dpi_clutch", "left_click", "right_click", "middle_click",
            "scroll_up", "scroll_down", "mouse_back", "mouse_forward",
            "keyboard_simple", "clear_layer",
        ]
        guard validKinds.contains(kindRaw) else {
            throw ProbeError.usage("Invalid --kind '\(kindRaw)'\n\(usageText)")
        }

        let hidKey = max(0, min(255, Int(flags["--hid-key"] ?? "4") ?? 4))
        let turboEnabled = parseBoolean(flags["--turbo"] ?? "off")
        let turboRate = max(1, min(255, Int(flags["--turbo-rate"] ?? "142") ?? 142))
        let clutchDPI = Int(flags["--clutch-dpi"] ?? "").map { max(100, min(30_000, $0)) }
        let profiles = try parseUSBProfiles(flags["--profile"], defaultProfiles: [0x01, 0x00])
        return (slot, kindRaw, hidKey, turboEnabled, turboRate, clutchDPI, profiles, try parseOptionalUSBPID(args))
    }

    private static func parseUSBButtonSetRawArgs(_ args: [String]) throws -> (slot: Int, functionBlock: [UInt8], profiles: [UInt8], productID: Int?) {
        let flags = parseFlags(args)
        guard let slotRaw = flags["--slot"], let slot = Int(slotRaw) else {
            throw ProbeError.usage("Missing --slot\n\(usageText)")
        }
        guard let hexRaw = flags["--hex"] else {
            throw ProbeError.usage("Missing --hex\n\(usageText)")
        }
        let functionBlock = try parseHexBytes(hexRaw)
        guard functionBlock.count == 7 else {
            throw ProbeError.usage("--hex must decode to exactly 7 bytes")
        }
        let profiles = try parseUSBProfiles(flags["--profile"], defaultProfiles: [0x01, 0x00])
        return (slot, functionBlock, profiles, try parseOptionalUSBPID(args))
    }

    private static func parseUSBInputListenArgs(_ args: [String]) throws -> (durationSeconds: TimeInterval, maxReports: Int?, productID: Int?) {
        let flags = parseFlags(args)
        let durationSeconds = max(0.5, Double(flags["--duration"] ?? "15") ?? 15.0)
        let maxReportsRaw = max(0, Int(flags["--max-reports"] ?? "0") ?? 0)
        let maxReports = maxReportsRaw > 0 ? maxReportsRaw : nil
        return (durationSeconds, maxReports, try parseOptionalUSBPID(args))
    }

    private static func parseUSBProfileReadArgs(_ args: [String]) throws -> (profiles: [UInt8], buttonSlots: [UInt8], includeEffective: Bool, productID: Int?) {
        let flags = parseFlags(args)
        let profiles: [UInt8]
        if let raw = flags["--profiles"] {
            profiles = try parseUInt8List(raw)
            guard !profiles.isEmpty else { throw ProbeError.usage("Empty --profiles") }
        } else if let raw = flags["--stored-slots"] {
            let storedSlots = try parseUInt8List(raw)
            guard !storedSlots.isEmpty else { throw ProbeError.usage("Empty --stored-slots") }
            for storedSlot in storedSlots where !(1...4).contains(storedSlot) {
                throw ProbeError.usage("Invalid --stored-slots value '\(storedSlot)' (expected 1..4)")
            }
            profiles = storedSlots.map { $0 &+ 1 }
        } else {
            profiles = [0x02, 0x03, 0x04, 0x05]
        }

        let buttonSlotsRaw = flags["--button-slots"] ?? "5"
        let normalizedButtonSlots = buttonSlotsRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let buttonSlots: [UInt8]
        if normalizedButtonSlots.isEmpty || normalizedButtonSlots == "none" || normalizedButtonSlots == "off" {
            buttonSlots = []
        } else {
            buttonSlots = try parseUInt8List(buttonSlotsRaw)
        }

        let includeEffective = parseBoolean(flags["--include-effective"] ?? flags["--include-live"] ?? "on")
        return (
            uniqueByteList(profiles),
            uniqueByteList(buttonSlots),
            includeEffective,
            try parseOptionalUSBPID(args)
        )
    }

    private static func parseUSBProfileVerifyWritesArgs(
        _ args: [String],
        command: String = "usb-profile-verify-writes"
    ) throws -> (profile: UInt8, productID: Int?) {
        let flags = parseFlags(args)
        guard parseBoolean(flags["--yes"] ?? "off") else {
            throw ProbeError.usage("\(command) sends guarded writes to a stored profile; pass --yes to continue\n\(usageText)")
        }

        let profile = try parseUSBStoredProfile(flags: flags, command: command)
        return (profile, try parseOptionalUSBPID(args))
    }

    private static func parseUSBProfileActiveSetArgs(_ args: [String]) throws -> (profile: UInt8, productID: Int?) {
        let flags = parseFlags(args)
        guard parseBoolean(flags["--yes"] ?? "off") else {
            throw ProbeError.usage("usb-profile-active-set changes the hardware-active USB profile; pass --yes to continue\n\(usageText)")
        }

        let profile: UInt8
        if let raw = flags["--profile"] {
            guard let parsed = parseUInt8(raw) else {
                throw ProbeError.usage("Invalid --profile '\(raw)'")
            }
            profile = parsed
        } else if let raw = flags["--stored-slot"] {
            guard let storedSlot = parseUInt8(raw), (1...4).contains(storedSlot) else {
                throw ProbeError.usage("Invalid --stored-slot '\(raw)' (expected 1..4)")
            }
            profile = storedSlot &+ 1
        } else {
            throw ProbeError.usage("Missing --profile or --stored-slot\n\(usageText)")
        }

        guard (0x01...0x05).contains(profile) else {
            throw ProbeError.usage("usb-profile-active-set targets known USB profiles 1..5, not profile \(profile)")
        }
        return (profile, try parseOptionalUSBPID(args))
    }

    private static func parseUSBProfileDeleteArgs(_ args: [String]) throws -> (profile: UInt8, productID: Int?) {
        let flags = parseFlags(args)
        guard parseBoolean(flags["--yes"] ?? "off") else {
            throw ProbeError.usage("usb-profile-delete unassigns a stored profile from the hardware cycle ring; pass --yes to continue\n\(usageText)")
        }

        let profile = try parseUSBStoredProfile(flags: flags, command: "usb-profile-delete")
        return (profile, try parseOptionalUSBPID(args))
    }

    private static func parseUSBStoredProfile(flags: [String: String], command: String) throws -> UInt8 {
        let profile: UInt8
        if let raw = flags["--profile"] {
            guard let parsed = parseUInt8(raw) else {
                throw ProbeError.usage("Invalid --profile '\(raw)'")
            }
            profile = parsed
        } else if let raw = flags["--stored-slot"] {
            guard let storedSlot = parseUInt8(raw), (1...4).contains(storedSlot) else {
                throw ProbeError.usage("Invalid --stored-slot '\(raw)' (expected 1..4)")
            }
            profile = storedSlot &+ 1
        } else {
            throw ProbeError.usage("Missing --profile or --stored-slot\n\(usageText)")
        }

        guard (0x02...0x05).contains(profile) else {
            throw ProbeError.usage("\(command) only targets known stored USB profiles 2..5, not live/base profile \(profile)")
        }
        return profile
    }

    private static func parseBTRawReadArgs(_ args: [String]) throws -> (key: [UInt8], preferredPeripheralName: String?, timeoutSeconds: TimeInterval) {
        let flags = parseFlags(args)
        guard let keyRaw = flags["--key"] else {
            throw ProbeError.usage("Missing --key\n\(usageText)")
        }
        let key = try parseHexBytes(keyRaw)
        guard key.count == 4 else {
            throw ProbeError.usage("Invalid --key '\(keyRaw)' (expected 8 hex chars)")
        }
        let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "600").map { $0 / 1000.0 } ?? 0.6)
        let preferredPeripheralName = parsePeripheralName(flags["--name"])
        return (key, preferredPeripheralName, timeoutSeconds)
    }

    private static func parseBTRawWriteArgs(_ args: [String]) throws -> (key: [UInt8], payload: [UInt8], preferredPeripheralName: String?, timeoutSeconds: TimeInterval) {
        let flags = parseFlags(args)
        guard let keyRaw = flags["--key"] else {
            throw ProbeError.usage("Missing --key\n\(usageText)")
        }
        guard let payloadRaw = flags["--payload"] else {
            throw ProbeError.usage("Missing --payload\n\(usageText)")
        }
        let key = try parseHexBytes(keyRaw)
        guard key.count == 4 else {
            throw ProbeError.usage("Invalid --key '\(keyRaw)' (expected 8 hex chars)")
        }
        let payload = try parseHexBytes(payloadRaw)
        let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "900").map { $0 / 1000.0 } ?? 0.9)
        let preferredPeripheralName = parsePeripheralName(flags["--name"])
        return (key, payload, preferredPeripheralName, timeoutSeconds)
    }

    private static func parseBTProfileReadArgs(_ args: [String]) throws -> (preferredPeripheralName: String?, targets: [UInt8], buttonSlots: [UInt8], includeLiveButtons: Bool, timeoutSeconds: TimeInterval) {
        let flags = parseFlags(args)
        let targets = try parseBTProfileTargets(flags: flags)
        let buttonSlots = try parseUInt8List(flags["--button-slots"] ?? "")
        let includeLiveButtons = parseBoolean(flags["--include-live-buttons"] ?? "off")
        let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "900").map { $0 / 1000.0 } ?? 0.9)
        let preferredPeripheralName = parsePeripheralName(flags["--name"])
        return (preferredPeripheralName, targets, buttonSlots, includeLiveButtons, timeoutSeconds)
    }

    private static func parseBTProfileActiveSetArgs(_ args: [String]) throws -> (preferredPeripheralName: String?, target: UInt8, timeoutSeconds: TimeInterval) {
        let flags = parseFlags(args)
        guard parseBoolean(flags["--yes"] ?? "off") else {
            throw ProbeError.usage("bt-profile-active-set changes the hardware-active Bluetooth target; pass --yes to continue\n\(usageText)")
        }
        let target = try parseBTProfileTarget(flags: flags)
        guard (0x01...0x05).contains(target) else {
            throw ProbeError.usage("bt-profile-active-set targets known Bluetooth profile targets 1..5, not target \(target)")
        }
        let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "1200").map { $0 / 1000.0 } ?? 1.2)
        let preferredPeripheralName = parsePeripheralName(flags["--name"])
        return (preferredPeripheralName, target, timeoutSeconds)
    }

    private static func parseBTProfileCreateArgs(_ args: [String]) throws -> (preferredPeripheralName: String?, target: UInt8, guid: UUID, profileName: String, owner: String, values: [Int], active: Int, brightness: UInt8, timeoutSeconds: TimeInterval) {
        let flags = parseFlags(args)
        guard parseBoolean(flags["--yes"] ?? "off") else {
            throw ProbeError.usage("bt-profile-create clears and rewrites a persistent onboard target; pass --yes to continue\n\(usageText)")
        }
        let target = try parseBTProfileTarget(flags: flags)
        guard target >= 0x02 else {
            throw ProbeError.usage("bt-profile-create expects a stored target (use --stored-slot 1..4 or --target 2..5)")
        }
        let profileName = flags["--profile-name"] ?? "OPENSNEK_MAC_SLOT_\(max(1, Int(target) - 1))"
        _ = try asciiBytes(profileName, maxLength: 0x74 - 0x10, fieldName: "--profile-name")

        let owner = flags["--owner"] ?? "31933b5452df5708882d4fb55d0b2905f16d829500fe936c56f98d5cd0241a76"
        let ownerBytes = try asciiBytes(owner, maxLength: 64, fieldName: "--owner")
        guard ownerBytes.count == 64 else {
            throw ProbeError.usage("--owner must be exactly 64 ASCII bytes")
        }

        let guid: UUID
        if let guidRaw = flags["--guid"] {
            guard let parsed = UUID(uuidString: guidRaw) else {
                throw ProbeError.usage("Invalid --guid '\(guidRaw)'")
            }
            guid = parsed
        } else {
            guid = UUID()
        }

        let values = try parseValues(flags["--values"] ?? "400,800,1600,3200,6400")
        let active = max(0, min(values.count - 1, (Int(flags["--active"] ?? "3") ?? 3) - 1))
        let brightness = UInt8(max(0, min(255, Int(flags["--brightness"] ?? "84") ?? 84)))
        let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "1400").map { $0 / 1000.0 } ?? 1.4)
        let preferredPeripheralName = parsePeripheralName(flags["--name"])
        return (preferredPeripheralName, target, guid, profileName, owner, values, active, brightness, timeoutSeconds)
    }

    private static func parseBTProfileButtonReadArgs(_ args: [String]) throws -> (preferredPeripheralName: String?, target: UInt8, buttonSlot: UInt8, timeoutSeconds: TimeInterval) {
        let flags = parseFlags(args)
        guard let slotRaw = flags["--button-slot"] ?? flags["--slot"],
              let buttonSlot = parseUInt8(slotRaw) else {
            throw ProbeError.usage("Missing or invalid --button-slot\n\(usageText)")
        }
        let target = try parseBTProfileTarget(flags: flags)
        let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "900").map { $0 / 1000.0 } ?? 0.9)
        let preferredPeripheralName = parsePeripheralName(flags["--name"])
        return (preferredPeripheralName, target, buttonSlot, timeoutSeconds)
    }

    private static func parseBTProfileButtonSetArgs(_ args: [String]) throws -> (preferredPeripheralName: String?, target: UInt8, buttonSlot: UInt8, payload: [UInt8], projectLive: Bool, timeoutSeconds: TimeInterval) {
        let flags = parseFlags(args)
        guard parseBoolean(flags["--yes"] ?? "off") else {
            throw ProbeError.usage("bt-profile-button-set writes persistent onboard target data; pass --yes to continue\n\(usageText)")
        }
        guard let slotRaw = flags["--button-slot"] ?? flags["--slot"],
              let buttonSlot = parseUInt8(slotRaw) else {
            throw ProbeError.usage("Missing or invalid --button-slot\n\(usageText)")
        }
        let target = try parseBTProfileTarget(flags: flags)
        guard target >= 0x02 else {
            throw ProbeError.usage("bt-profile-button-set expects a stored target (use --stored-slot 1..4 or --target 2..5)")
        }

        let payload: [UInt8]
        if let payloadRaw = flags["--payload"] {
            payload = try parseHexBytes(payloadRaw)
            guard payload.count == 10 else {
                throw ProbeError.usage("--payload must decode to exactly 10 bytes")
            }
            guard payload[0] == target, payload[1] == buttonSlot else {
                throw ProbeError.usage(
                    "--payload first bytes must match target/button-slot (expected \(String(format: "%02x %02x", target, buttonSlot)))"
                )
            }
        } else {
            let kindRaw = flags["--kind"] ?? ButtonBindingKind.keyboardSimple.rawValue
            guard let kind = ButtonBindingKind(rawValue: kindRaw) else {
                throw ProbeError.usage("Invalid --kind '\(kindRaw)'")
            }
            let hidKey = parseUInt8(flags["--hid-key"] ?? "") ?? 0x09
            let hidModifiers = parseUInt8(flags["--hid-modifiers"] ?? "") ?? 0x00
            let turboEnabled = parseBoolean(flags["--turbo"] ?? "off")
            let turboRate = UInt16(max(1, min(255, Int(flags["--turbo-rate"] ?? "142") ?? 142)))
            let livePayload = BLEVendorProtocol.buildButtonPayload(
                slot: buttonSlot,
                kind: kind,
                hidKey: hidKey,
                hidModifiers: hidModifiers,
                turboEnabled: turboEnabled && kind.supportsTurbo,
                turboRate: turboRate
            )
            payload = Array(BLEVendorProtocol.retargetButtonPayload(livePayload, target: target, slot: buttonSlot))
        }

        let projectLive = parseBoolean(flags["--project-live"] ?? "off")
        let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "1100").map { $0 / 1000.0 } ?? 1.1)
        let preferredPeripheralName = parsePeripheralName(flags["--name"])
        return (preferredPeripheralName, target, buttonSlot, payload, projectLive, timeoutSeconds)
    }

    private static func parseBTProfileHIDWatchArgs(_ args: [String]) throws -> (durationSeconds: TimeInterval, maxReports: Int?, productID: Int?, preferredPeripheralName: String?) {
        let flags = parseFlags(args)
        let durationSeconds = max(0.5, Double(flags["--duration"] ?? "20") ?? 20.0)
        let maxReportsRaw = max(0, Int(flags["--max-reports"] ?? "0") ?? 0)
        let maxReports = maxReportsRaw > 0 ? maxReportsRaw : nil
        let productID = try parseOptionalBTPID(args) ?? 0x00AC
        let preferredPeripheralName = parsePeripheralName(flags["--name"])
        return (durationSeconds, maxReports, productID, preferredPeripheralName)
    }

    private static func parseBTProfileWatchArgs(_ args: [String]) throws -> (preferredPeripheralName: String?, buttonSlot: UInt8, pollMs: Int, samples: Int, timeoutSeconds: TimeInterval) {
        let flags = parseFlags(args)
        let buttonSlot = UInt8(max(0, min(255, Int(flags["--slot"] ?? "4") ?? 4)))
        let pollMs = max(0, Int(flags["--poll-ms"] ?? "1000") ?? 1000)
        let samples = max(1, Int(flags["--samples"] ?? "20") ?? 20)
        let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "900").map { $0 / 1000.0 } ?? 0.9)
        let preferredPeripheralName = parsePeripheralName(flags["--name"])
        return (preferredPeripheralName, buttonSlot, pollMs, samples, timeoutSeconds)
    }

    private static func parseBTLightingZoneArgs(_ args: [String]) throws -> (zoneID: String?, preferredPeripheralName: String?) {
        let flags = parseFlags(args)
        return (parseLightingZoneID(flags["--zone"]), parsePeripheralName(flags["--name"]))
    }

    private static func parseBTLightingBrightnessArgs(_ args: [String]) throws -> (value: Int, zoneID: String?, preferredPeripheralName: String?) {
        let flags = parseFlags(args)
        guard let valueRaw = flags["--value"], let value = Int(valueRaw) else {
            throw ProbeError.usage("Missing --value\n\(usageText)")
        }
        return (
            max(0, min(255, value)),
            parseLightingZoneID(flags["--zone"]),
            parsePeripheralName(flags["--name"])
        )
    }

    private static func parseBTLightingColorArgs(_ args: [String]) throws -> (color: RGBPatch, zoneID: String?, preferredPeripheralName: String?) {
        let flags = parseFlags(args)
        guard let color = try parseRGBPatch(flags["--color"]) else {
            throw ProbeError.usage("Missing or invalid --color\n\(usageText)")
        }
        return (
            color,
            parseLightingZoneID(flags["--zone"]),
            parsePeripheralName(flags["--name"])
        )
    }

    private static func parseUSBLightingZoneArgs(_ args: [String]) throws -> (zoneID: String?, productID: Int?) {
        let flags = parseFlags(args)
        return (parseLightingZoneID(flags["--zone"]), try parseOptionalUSBPID(args))
    }

    private static func parseUSBLightingBrightnessArgs(_ args: [String]) throws -> (value: Int, zoneID: String?, productID: Int?) {
        let flags = parseFlags(args)
        guard let valueRaw = flags["--value"], let value = Int(valueRaw) else {
            throw ProbeError.usage("Missing --value\n\(usageText)")
        }
        return (max(0, min(255, value)), parseLightingZoneID(flags["--zone"]), try parseOptionalUSBPID(args))
    }

    private static func parseUSBLightingEffectArgs(_ args: [String]) throws -> (effect: LightingEffectPatch, zoneID: String?, productID: Int?) {
        let flags = parseFlags(args)
        guard let kindRaw = flags["--kind"], let kind = parseLightingEffectKind(kindRaw) else {
            throw ProbeError.usage("Missing or invalid --kind\n\(usageText)")
        }

        let primary = try parseRGBPatch(flags["--color"]) ?? RGBPatch(r: 0, g: 255, b: 0)
        let secondary = try parseRGBPatch(flags["--secondary"]) ?? RGBPatch(r: 0, g: 170, b: 255)
        let direction = try parseLightingDirection(flags["--direction"] ?? "left")
        let speed = max(1, min(4, Int(flags["--speed"] ?? "2") ?? 2))
        let effect = LightingEffectPatch(
            kind: kind,
            primary: primary,
            secondary: secondary,
            waveDirection: direction,
            reactiveSpeed: speed
        )
        return (effect, parseLightingZoneID(flags["--zone"]), try parseOptionalUSBPID(args))
    }

    private static func parseUSBRawArgs(_ args: [String]) throws -> (classID: UInt8, cmdID: UInt8, size: UInt8, args: [UInt8], noTxnRescan: Bool, responseAttempts: Int, responseDelayUs: useconds_t, productID: Int?) {
        let flags = parseFlags(args)
        guard let classRaw = flags["--class"], let classID = parseUInt8(classRaw) else {
            throw ProbeError.usage("Missing or invalid --class\n\(usageText)")
        }
        guard let cmdRaw = flags["--cmd"], let cmdID = parseUInt8(cmdRaw) else {
            throw ProbeError.usage("Missing or invalid --cmd\n\(usageText)")
        }
        let parsedArgs = try parseCSVBytes(flags["--args"] ?? "")
        let size = parseUInt8(flags["--size"] ?? "") ?? UInt8(parsedArgs.count)
        let noTxnRescan = parseBoolean(flags["--no-txn-rescan"] ?? "off")
        let responseAttempts = max(1, Int(flags["--response-attempts"] ?? "12") ?? 12)
        let responseDelayUs = useconds_t(max(1_000, Int(flags["--response-delay-us"] ?? "40000") ?? 40_000))
        return (classID, cmdID, size, parsedArgs, noTxnRescan, responseAttempts, responseDelayUs, try parseOptionalUSBPID(args))
    }

    private static func parseOptionalUSBPID(_ args: [String]) throws -> Int? {
        let flags = parseFlags(args)
        guard let raw = flags["--pid"] else { return nil }
        guard let value = parseUInt16(raw) else {
            throw ProbeError.usage("Invalid --pid '\(raw)'")
        }
        return Int(value)
    }

    private static func parseOptionalBTPID(_ args: [String]) throws -> Int? {
        let flags = parseFlags(args)
        guard let raw = flags["--pid"] else { return nil }
        guard let value = parseUInt16(raw) else {
            throw ProbeError.usage("Invalid --pid '\(raw)'")
        }
        return Int(value)
    }

    private static func parseBTProfileTarget(flags: [String: String]) throws -> UInt8 {
        if let targetRaw = flags["--target"] {
            guard let target = parseUInt8(targetRaw) else {
                throw ProbeError.usage("Invalid --target '\(targetRaw)'")
            }
            return target
        }
        if let storedSlotRaw = flags["--stored-slot"] {
            guard let storedSlot = parseUInt8(storedSlotRaw), (1...4).contains(storedSlot) else {
                throw ProbeError.usage("Invalid --stored-slot '\(storedSlotRaw)' (expected 1..4)")
            }
            return storedSlot &+ 1
        }
        throw ProbeError.usage("Missing --stored-slot or --target\n\(usageText)")
    }

    private static func parseBTProfileTargets(flags: [String: String]) throws -> [UInt8] {
        if let targetsRaw = flags["--targets"] {
            let targets = try parseUInt8List(targetsRaw)
            guard !targets.isEmpty else { throw ProbeError.usage("Empty --targets") }
            return targets
        }
        if let storedSlotsRaw = flags["--stored-slots"] {
            let storedSlots = try parseUInt8List(storedSlotsRaw)
            guard !storedSlots.isEmpty else { throw ProbeError.usage("Empty --stored-slots") }
            for storedSlot in storedSlots where !(1...4).contains(storedSlot) {
                throw ProbeError.usage("Invalid --stored-slots value '\(storedSlot)' (expected 1..4)")
            }
            return storedSlots.map { $0 &+ 1 }
        }
        return [0x02, 0x03, 0x04, 0x05]
    }

    private static func parseUSBProfiles(_ raw: String?, defaultProfiles: [UInt8]) throws -> [UInt8] {
        guard let raw else { return defaultProfiles }
        let normalized = raw.lowercased()
        switch normalized {
        case "default", "persistent", "1":
            return [0x01]
        case "direct", "0":
            return [0x00]
        case "both", "all":
            return [0x01, 0x00]
        default:
            throw ProbeError.usage("Invalid --profile '\(raw)' (expected default/direct/both)")
        }
    }

    private static func parseFlags(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var i = 0
        while i < args.count {
            let key = args[i]
            if key.hasPrefix("--") {
                if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                    result[key] = args[i + 1]
                    i += 2
                } else {
                    result[key] = "true"
                    i += 1
                }
            } else {
                i += 1
            }
        }
        return result
    }

    private static func parseValues(_ raw: String) throws -> [Int] {
        let values = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let clipped = values.prefix(5).map { max(100, min(30_000, $0)) }
        guard !clipped.isEmpty else {
            throw ProbeError.usage("Invalid DPI values: \(raw)")
        }
        return clipped
    }

    private static func parseBoolean(_ raw: String) -> Bool {
        switch raw.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func parseLightingZoneID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "all" ? nil : normalized
    }

    private static func parsePeripheralName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseLightingEffectKind(_ raw: String) -> LightingEffectKind? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "off":
            return .off
        case "static", "static_color", "staticcolor":
            return .staticColor
        case "spectrum":
            return .spectrum
        case "wave":
            return .wave
        case "reactive":
            return .reactive
        case "pulse_random", "pulserandom", "random":
            return .pulseRandom
        case "pulse_single", "pulsesingle", "single":
            return .pulseSingle
        case "pulse_dual", "pulsedual", "dual":
            return .pulseDual
        default:
            return nil
        }
    }

    private static func parseLightingDirection(_ raw: String) throws -> LightingWaveDirection {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "left", "1":
            return .left
        case "right", "2":
            return .right
        default:
            throw ProbeError.usage("Invalid --direction '\(raw)' (expected left/right)")
        }
    }

    private static func parseRGBPatch(_ raw: String?) throws -> RGBPatch? {
        guard let raw else { return nil }
        let bytes = try parseHexBytes(raw)
        guard bytes.count == 3 else {
            throw ProbeError.usage("Invalid RGB hex '\(raw)' (expected 6 hex chars)")
        }
        return RGBPatch(r: Int(bytes[0]), g: Int(bytes[1]), b: Int(bytes[2]))
    }

    private static func parseHexBytes(_ raw: String) throws -> [UInt8] {
        let normalized = raw
            .replacingOccurrences(of: "0x", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
        guard normalized.count % 2 == 0 else {
            throw ProbeError.usage("Invalid hex byte string: \(raw)")
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(normalized.count / 2)
        var idx = normalized.startIndex
        while idx < normalized.endIndex {
            let next = normalized.index(idx, offsetBy: 2)
            let chunk = normalized[idx..<next]
            guard let value = UInt8(chunk, radix: 16) else {
                throw ProbeError.usage("Invalid hex byte string: \(raw)")
            }
            bytes.append(value)
            idx = next
        }
        return bytes
    }

    private static func parseUInt8List(_ raw: String) throws -> [UInt8] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try trimmed
            .split(separator: ",")
            .map { token -> UInt8 in
                let valueRaw = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = parseUInt8(valueRaw) else {
                    throw ProbeError.usage("Invalid byte value '\(valueRaw)'")
                }
                return value
            }
    }

    private static func asciiBytes(_ value: String, maxLength: Int, fieldName: String) throws -> [UInt8] {
        let bytes = Array(value.utf8)
        guard bytes.count <= maxLength else {
            throw ProbeError.usage("\(fieldName) must be \(maxLength) ASCII bytes or fewer")
        }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else {
            throw ProbeError.usage("\(fieldName) must contain printable ASCII only")
        }
        return bytes
    }

    private static func parseCSVBytes(_ raw: String) throws -> [UInt8] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try trimmed
            .split(separator: ",")
            .map { chunk in
                let token = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = parseCSVByte(token) else {
                    throw ProbeError.usage("Invalid byte value '\(token)'")
                }
                return value
            }
    }

    private static func parseCSVByte(_ raw: String) -> UInt8? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("0x") {
            return UInt8(trimmed.dropFirst(2), radix: 16)
        }
        if trimmed.count == 2 || trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefABCDEF")) != nil {
            return UInt8(trimmed, radix: 16)
        }
        return UInt8(trimmed, radix: 10)
    }

    private static func parseUInt8(_ raw: String) -> UInt8? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("0x") {
            return UInt8(trimmed.dropFirst(2), radix: 16)
        }
        return UInt8(trimmed, radix: 10)
    }

    private static func parseUInt16(_ raw: String) -> UInt16? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("0x") {
            return UInt16(trimmed.dropFirst(2), radix: 16)
        }
        return UInt16(trimmed, radix: 10)
    }

    private static func describeUSBFunctionBlock(_ block: [UInt8]) -> String {
        ButtonBindingSupport.describeUSBFunctionBlock(block)
    }

    private struct USBProfileReadRecord {
        let profile: UInt8
        var scalar: DpiPair?
        var stagePairs: [DpiPair] = []
        var stageIDs: [UInt8] = []
        var activeToken: UInt8?
        var brightnessByLED: [UInt8: Int] = [:]
        var buttonBySlot: [UInt8: [UInt8]] = [:]
    }

    private struct USBProfileBrightnessRecord {
        let target: USBLightingTargetDescriptor
        let value: Int
        let raw: [UInt8]
    }

    private struct USBProfileWritableSnapshot {
        let profile: UInt8
        let scalar: DpiPair
        let scalarRaw: [UInt8]
        let stagesRaw: [UInt8]
        let stagePairs: [DpiPair]
        let activeToken: UInt8
        let brightness: [USBProfileBrightnessRecord]
    }

    private static func printUSBProfileReadSweep(
        usb: USBProbeClient,
        profiles: [UInt8],
        buttonSlots: [UInt8],
        includeEffective: Bool
    ) throws {
        if let summary = try usb.readProfileSummaryRaw() {
            let activeHint = summary.first.map { String($0) } ?? "nil"
            let countHint = summary.count > 2 ? String(summary[2]) : "nil"
            print("summary class=00 cmd=87 payload=\(hexString(summary)) activeHint=\(activeHint) countHint=\(countHint)")
        } else {
            print("summary class=00 cmd=87 read_failed")
        }

        if let active = try usb.readActiveProfileID() {
            print("active-profile class=05 cmd=84 value=\(active) \(usbProfileLabel(active))")
        } else {
            print("active-profile class=05 cmd=84 read_failed")
        }

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
                    let chunkOffsets = metadataRead.chunks
                        .map { String(format: "0x%04x", $0.offset) }
                        .joined(separator: ",")
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
                print(
                    "dpi-stages \(label) activeToken=0x\(String(format: "%02x", stages.activeToken)) " +
                    "stageIDs=[\(stageIDs)] pairs=\(describeDpiPairs(stages.pairs)) raw=\(hexString(stages.raw))"
                )
            } else {
                print("dpi-stages \(label) read_failed")
            }

            for target in lightingTargets {
                if let brightness = try usb.readProfileLightingBrightness(profile: profile, ledID: target.ledID) {
                    if let value = brightness.brightness {
                        record.brightnessByLED[target.ledID] = value
                    }
                    let value = brightness.brightness.map(String.init) ?? "nil"
                    print(
                        "brightness \(label) zone=\(target.zoneID) led=0x\(String(format: "%02x", target.ledID)) " +
                        "value=\(value) raw=\(hexString(brightness.raw))"
                    )
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

        guard includeEffective, let effective = records.first(where: { $0.profile == 0x00 }) else {
            return
        }
        let effectiveFingerprint = usbProfileFingerprint(effective)
        let matches = records
            .filter { profiles.contains($0.profile) && usbProfileFingerprint($0) == effectiveFingerprint }
            .map(\.profile)
        if matches.isEmpty {
            print("fingerprint effective=\(usbProfileLabel(0x00)) match=none")
        } else if matches.count == 1, let match = matches.first {
            print("fingerprint effective=\(usbProfileLabel(0x00)) match=\(usbProfileLabel(match))")
        } else {
            print(
                "fingerprint effective=\(usbProfileLabel(0x00)) ambiguous=[" +
                matches.map(usbProfileLabel).joined(separator: ", ") +
                "]"
            )
        }
    }

    private static func usbProfileLabel(_ profile: UInt8) -> String {
        switch profile {
        case 0x00:
            return "effective(profile=0)"
        case 0x01:
            return "base(profile=1)"
        default:
            return "stored-slot=\(Int(profile) - 1)(profile=\(profile))"
        }
    }

    private static func usbProfileFingerprint(_ record: USBProfileReadRecord) -> String {
        let scalar = record.scalar.map { "\($0.x)x\($0.y)" } ?? "nil"
        let stages = record.stagePairs.map { "\($0.x)x\($0.y)" }.joined(separator: ",")
        let brightness = record.brightnessByLED.keys.sorted()
            .map { key in "0x\(String(format: "%02x", key))=\(record.brightnessByLED[key] ?? -1)" }
            .joined(separator: ",")
        let buttons = record.buttonBySlot.keys.sorted()
            .map { key in "0x\(String(format: "%02x", key))=\(hexString(record.buttonBySlot[key] ?? []))" }
            .joined(separator: ",")
        return [scalar, stages, brightness, buttons].joined(separator: "|")
    }

    private static func verifyUSBProfileSameValueWrites(usb: USBProbeClient, profile: UInt8) throws {
        let label = usbProfileLabel(profile)

        guard let scalarBefore = try usb.readProfileDPIScalar(profile: profile),
              let pairBefore = scalarBefore.pair
        else {
            throw ProbeError.protocolError("Unable to read DPI scalar before same-value write")
        }
        let scalarWrite = try usb.writeProfileDPIScalar(profile: profile, pair: pairBefore)
        guard let scalarAfter = try usb.readProfileDPIScalar(profile: profile),
              let pairAfter = scalarAfter.pair
        else {
            throw ProbeError.protocolError("Unable to read DPI scalar after same-value write")
        }
        print(
            "verify-write dpi-scalar \(label) " +
            "before=\(pairBefore.x)x\(pairBefore.y) after=\(pairAfter.x)x\(pairAfter.y) " +
            "rawBefore=\(hexString(scalarBefore.raw)) rawAfter=\(hexString(scalarAfter.raw)) status=\(scalarWrite && pairAfter == pairBefore ? "ok" : "mismatch")"
        )
        guard scalarWrite, pairAfter == pairBefore else {
            throw ProbeError.protocolError("DPI scalar same-value write did not round-trip")
        }

        guard let stagesBefore = try usb.readProfileDPIStages(profile: profile) else {
            throw ProbeError.protocolError("Unable to read DPI stages before same-value write")
        }
        let stagesWrite = try usb.writeProfileDPIStagesRaw(stagesBefore.raw)
        guard let stagesAfter = try usb.readProfileDPIStages(profile: profile) else {
            throw ProbeError.protocolError("Unable to read DPI stages after same-value write")
        }
        let stagesMatch = stagesAfter.activeToken == stagesBefore.activeToken &&
            stagesAfter.stageIDs == stagesBefore.stageIDs &&
            stagesAfter.pairs == stagesBefore.pairs
        print(
            "verify-write dpi-stages \(label) " +
            "beforeToken=0x\(String(format: "%02x", stagesBefore.activeToken)) " +
            "afterToken=0x\(String(format: "%02x", stagesAfter.activeToken)) " +
            "before=\(describeDpiPairs(stagesBefore.pairs)) after=\(describeDpiPairs(stagesAfter.pairs)) " +
            "status=\(stagesWrite && stagesMatch ? "ok" : "mismatch")"
        )
        guard stagesWrite, stagesMatch else {
            throw ProbeError.protocolError("DPI stages same-value write did not round-trip")
        }

        for target in usb.profileLightingTargets() {
            guard let brightnessBefore = try usb.readProfileLightingBrightness(profile: profile, ledID: target.ledID),
                  let valueBefore = brightnessBefore.brightness
            else {
                throw ProbeError.protocolError("Unable to read brightness before same-value write for LED 0x\(String(format: "%02x", target.ledID))")
            }
            let brightnessWrite = try usb.writeProfileLightingBrightness(profile: profile, ledID: target.ledID, brightness: valueBefore)
            guard let brightnessAfter = try usb.readProfileLightingBrightness(profile: profile, ledID: target.ledID),
                  let valueAfter = brightnessAfter.brightness
            else {
                throw ProbeError.protocolError("Unable to read brightness after same-value write for LED 0x\(String(format: "%02x", target.ledID))")
            }
            print(
                "verify-write brightness \(label) zone=\(target.zoneID) led=0x\(String(format: "%02x", target.ledID)) " +
                "before=\(valueBefore) after=\(valueAfter) " +
                "rawBefore=\(hexString(brightnessBefore.raw)) rawAfter=\(hexString(brightnessAfter.raw)) " +
                "status=\(brightnessWrite && valueAfter == valueBefore ? "ok" : "mismatch")"
            )
            guard brightnessWrite, valueAfter == valueBefore else {
                throw ProbeError.protocolError("Brightness same-value write did not round-trip for LED 0x\(String(format: "%02x", target.ledID))")
            }
        }
    }

    private static func verifyUSBProfileChangedValueWrites(usb: USBProbeClient, profile: UInt8) throws {
        let label = usbProfileLabel(profile)
        let original = try readUSBProfileWritableSnapshot(usb: usb, profile: profile)
        let changedScalar = DpiPair(
            x: changedUSBProfileDPIValue(original.scalar.x),
            y: changedUSBProfileDPIValue(original.scalar.y)
        )
        let changedStagesRaw = try changedUSBProfileStageRaw(original.stagesRaw)
        let changedBrightness = Dictionary(
            uniqueKeysWithValues: original.brightness.map { record in
                (record.target.ledID, changedUSBProfileBrightnessValue(record.value))
            }
        )

        var wroteAny = false
        do {
            let scalarWrite = try usb.writeProfileDPIScalar(profile: profile, pair: changedScalar)
            wroteAny = wroteAny || scalarWrite
            guard let scalarAfter = try usb.readProfileDPIScalar(profile: profile),
                  let scalarPairAfter = scalarAfter.pair
            else {
                throw ProbeError.protocolError("Unable to read DPI scalar after changed-value write")
            }
            print(
                "verify-changed dpi-scalar \(label) " +
                "original=\(original.scalar.x)x\(original.scalar.y) changed=\(changedScalar.x)x\(changedScalar.y) " +
                "after=\(scalarPairAfter.x)x\(scalarPairAfter.y) rawAfter=\(hexString(scalarAfter.raw)) " +
                "status=\(scalarWrite && scalarPairAfter == changedScalar ? "ok" : "mismatch")"
            )
            guard scalarWrite, scalarPairAfter == changedScalar else {
                throw ProbeError.protocolError("DPI scalar changed-value write did not round-trip")
            }

            let stagesWrite = try usb.writeProfileDPIStagesRaw(changedStagesRaw)
            wroteAny = wroteAny || stagesWrite
            guard let stagesAfter = try usb.readProfileDPIStages(profile: profile) else {
                throw ProbeError.protocolError("Unable to read DPI stages after changed-value write")
            }
            print(
                "verify-changed dpi-stages \(label) " +
                "original=\(describeDpiPairs(original.stagePairs)) after=\(describeDpiPairs(stagesAfter.pairs)) " +
                "expectedRaw=\(hexString(changedStagesRaw)) rawAfter=\(hexString(stagesAfter.raw)) " +
                "status=\(stagesWrite && stagesAfter.raw == changedStagesRaw ? "ok" : "mismatch")"
            )
            guard stagesWrite, stagesAfter.raw == changedStagesRaw else {
                throw ProbeError.protocolError("DPI stages changed-value write did not round-trip")
            }

            for record in original.brightness {
                guard let changedValue = changedBrightness[record.target.ledID] else { continue }
                let brightnessWrite = try usb.writeProfileLightingBrightness(
                    profile: profile,
                    ledID: record.target.ledID,
                    brightness: changedValue
                )
                wroteAny = wroteAny || brightnessWrite
                guard let brightnessAfter = try usb.readProfileLightingBrightness(profile: profile, ledID: record.target.ledID),
                      let valueAfter = brightnessAfter.brightness
                else {
                    throw ProbeError.protocolError("Unable to read brightness after changed-value write for LED 0x\(String(format: "%02x", record.target.ledID))")
                }
                print(
                    "verify-changed brightness \(label) zone=\(record.target.zoneID) led=0x\(String(format: "%02x", record.target.ledID)) " +
                    "original=\(record.value) changed=\(changedValue) after=\(valueAfter) " +
                    "rawAfter=\(hexString(brightnessAfter.raw)) " +
                    "status=\(brightnessWrite && valueAfter == changedValue ? "ok" : "mismatch")"
                )
                guard brightnessWrite, valueAfter == changedValue else {
                    throw ProbeError.protocolError("Brightness changed-value write did not round-trip for LED 0x\(String(format: "%02x", record.target.ledID))")
                }
            }

            try restoreUSBProfileWritableSnapshot(usb: usb, snapshot: original, label: label)
        } catch {
            if wroteAny {
                print("verify-changed restore-after-error \(label) starting")
                do {
                    try restoreUSBProfileWritableSnapshot(usb: usb, snapshot: original, label: label)
                } catch {
                    print("verify-changed restore-after-error \(label) failed=\(error.localizedDescription)")
                }
            }
            throw error
        }
    }

    private static func readUSBProfileWritableSnapshot(usb: USBProbeClient, profile: UInt8) throws -> USBProfileWritableSnapshot {
        guard let scalarRead = try usb.readProfileDPIScalar(profile: profile),
              let scalar = scalarRead.pair
        else {
            throw ProbeError.protocolError("Unable to read stored-profile DPI scalar snapshot")
        }
        guard let stagesRead = try usb.readProfileDPIStages(profile: profile) else {
            throw ProbeError.protocolError("Unable to read stored-profile DPI stage snapshot")
        }
        var brightness: [USBProfileBrightnessRecord] = []
        for target in usb.profileLightingTargets() {
            guard let read = try usb.readProfileLightingBrightness(profile: profile, ledID: target.ledID),
                  let value = read.brightness
            else {
                throw ProbeError.protocolError("Unable to read brightness snapshot for LED 0x\(String(format: "%02x", target.ledID))")
            }
            brightness.append(USBProfileBrightnessRecord(target: target, value: value, raw: read.raw))
        }
        return USBProfileWritableSnapshot(
            profile: profile,
            scalar: scalar,
            scalarRaw: scalarRead.raw,
            stagesRaw: stagesRead.raw,
            stagePairs: stagesRead.pairs,
            activeToken: stagesRead.activeToken,
            brightness: brightness
        )
    }

    private static func restoreUSBProfileWritableSnapshot(
        usb: USBProbeClient,
        snapshot: USBProfileWritableSnapshot,
        label: String
    ) throws {
        let scalarWrite = try usb.writeProfileDPIScalar(profile: snapshot.profile, pair: snapshot.scalar)
        guard let scalarAfter = try usb.readProfileDPIScalar(profile: snapshot.profile),
              let scalarPairAfter = scalarAfter.pair
        else {
            throw ProbeError.protocolError("Unable to read DPI scalar after restore")
        }
        print(
            "verify-restore dpi-scalar \(label) " +
            "restored=\(scalarPairAfter.x)x\(scalarPairAfter.y) rawAfter=\(hexString(scalarAfter.raw)) " +
            "status=\(scalarWrite && scalarPairAfter == snapshot.scalar ? "ok" : "mismatch")"
        )
        guard scalarWrite, scalarPairAfter == snapshot.scalar else {
            throw ProbeError.protocolError("DPI scalar restore did not round-trip")
        }

        let stagesWrite = try usb.writeProfileDPIStagesRaw(snapshot.stagesRaw)
        guard let stagesAfter = try usb.readProfileDPIStages(profile: snapshot.profile) else {
            throw ProbeError.protocolError("Unable to read DPI stages after restore")
        }
        print(
            "verify-restore dpi-stages \(label) " +
            "restored=\(describeDpiPairs(stagesAfter.pairs)) rawAfter=\(hexString(stagesAfter.raw)) " +
            "status=\(stagesWrite && stagesAfter.raw == snapshot.stagesRaw ? "ok" : "mismatch")"
        )
        guard stagesWrite, stagesAfter.raw == snapshot.stagesRaw else {
            throw ProbeError.protocolError("DPI stages restore did not round-trip")
        }

        for record in snapshot.brightness {
            let brightnessWrite = try usb.writeProfileLightingBrightness(
                profile: snapshot.profile,
                ledID: record.target.ledID,
                brightness: record.value
            )
            guard let brightnessAfter = try usb.readProfileLightingBrightness(profile: snapshot.profile, ledID: record.target.ledID),
                  let valueAfter = brightnessAfter.brightness
            else {
                throw ProbeError.protocolError("Unable to read brightness after restore for LED 0x\(String(format: "%02x", record.target.ledID))")
            }
            print(
                "verify-restore brightness \(label) zone=\(record.target.zoneID) led=0x\(String(format: "%02x", record.target.ledID)) " +
                "restored=\(valueAfter) rawAfter=\(hexString(brightnessAfter.raw)) " +
                "status=\(brightnessWrite && valueAfter == record.value ? "ok" : "mismatch")"
            )
            guard brightnessWrite, valueAfter == record.value else {
                throw ProbeError.protocolError("Brightness restore did not round-trip for LED 0x\(String(format: "%02x", record.target.ledID))")
            }
        }
    }

    private static func changedUSBProfileDPIValue(_ value: Int) -> Int {
        if value <= 29_900 {
            return value + 100
        }
        return max(100, value - 100)
    }

    private static func changedUSBProfileBrightnessValue(_ value: Int) -> Int {
        value < 255 ? value + 1 : max(0, value - 1)
    }

    private static func changedUSBProfileStageRaw(_ raw: [UInt8]) throws -> [UInt8] {
        guard raw.count >= 10 else {
            throw ProbeError.protocolError("DPI stage raw payload is too short to mutate safely")
        }
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

    private struct BTProfileDPIRead {
        let target: UInt8
        let scalarRaw: Data?
        let scalar: DpiPair?
        let pairListRaw: Data?
        let pairs: [DpiPair]
        let tokenRaw: Data?
    }

    private struct BTProfileLightingRead {
        let target: UInt8
        let ledID: UInt8
        let brightnessRaw: Data?
        let brightness: UInt8?
        let stateRaw: Data?
        let color: RGBPatch?
    }

    private static func printBTProfileReadSweep(
        bridge: ProbeBridge,
        preferredPeripheralName: String?,
        timeoutSeconds: TimeInterval,
        targets: [UInt8],
        buttonSlots: [UInt8],
        includeLiveButtons: Bool
    ) async throws {
        let inventoryKey = BLEVendorProtocol.Key.profileTargetsGet().bytes
        let inventory = try await bridge.rawRead(
            key: inventoryKey,
            timeout: timeoutSeconds,
            preferredPeripheralName: preferredPeripheralName
        )
        print("inventory key=\(hexString(inventoryKey)) payload=\(inventory.payload.map { hexString(Array($0)) } ?? "nil")")

        let activeTargetKey = BLEVendorProtocol.Key.profileActiveTargetGet().bytes
        let activeTarget = try await bridge.rawRead(
            key: activeTargetKey,
            timeout: timeoutSeconds,
            preferredPeripheralName: preferredPeripheralName
        )
        let activeTargetPayload = activeTarget.payload.map { Array($0) } ?? []
        let activeTargetLabel: String
        if activeTargetPayload.count == 1 {
            activeTargetLabel = btProfileTargetLabel(activeTargetPayload[0])
        } else {
            activeTargetLabel = "unavailable"
        }
        print(
            "active-target key=\(hexString(activeTargetKey)) " +
            "payload=\(activeTarget.payload.map { hexString(Array($0)) } ?? "nil") " +
            "target=\(activeTargetLabel)"
        )

        var dpiReads: [BTProfileDPIRead] = []
        let dpiTargets = uniqueByteList([0x00] + targets)
        for target in dpiTargets {
            let read = try await readBTProfileDPI(
                bridge: bridge,
                preferredPeripheralName: preferredPeripheralName,
                timeoutSeconds: timeoutSeconds,
                target: target
            )
            dpiReads.append(read)
            print(describeBTProfileDPIRead(read))
        }

        let activePairs = dpiReads.first(where: { $0.target == 0x00 })?.pairs ?? []
        let storedMatches = dpiReads
            .filter { $0.target >= 0x02 && !$0.pairs.isEmpty && $0.pairs == activePairs }
            .map(\.target)
        if activePairs.isEmpty {
            print("fingerprint active=unavailable")
        } else if storedMatches.isEmpty {
            print("fingerprint active=\(describeDpiPairs(activePairs)) match=none")
        } else if storedMatches.count == 1, let match = storedMatches.first {
            print("fingerprint active=\(describeDpiPairs(activePairs)) match=\(btProfileTargetLabel(match))")
        } else {
            print(
                "fingerprint active=\(describeDpiPairs(activePairs)) ambiguous=[" +
                storedMatches.map(btProfileTargetLabel).joined(separator: ", ") +
                "]"
            )
        }

        let ledIDs = try await readBTProfileLightingLEDIDs(
            bridge: bridge,
            preferredPeripheralName: preferredPeripheralName,
            timeoutSeconds: timeoutSeconds
        )
        if !ledIDs.isEmpty {
            print("lighting-leds ids=\(ledIDs.map { String(format: "0x%02x", $0) }.joined(separator: ","))")
            for target in uniqueByteList([0x00, 0x01] + targets) {
                for ledID in ledIDs {
                    let read = try await readBTProfileLighting(
                        bridge: bridge,
                        preferredPeripheralName: preferredPeripheralName,
                        timeoutSeconds: timeoutSeconds,
                        target: target,
                        ledID: ledID
                    )
                    print(describeBTProfileLightingRead(read))
                }
            }
        }

        guard !buttonSlots.isEmpty else { return }
        let buttonTargets = includeLiveButtons ? uniqueByteList([0x00, 0x01] + targets) : targets
        for target in buttonTargets {
            for slot in buttonSlots {
                let key = BLEVendorProtocol.Key.buttonBindGet(target: target, slot: slot).bytes
                let result = try await bridge.rawRead(
                    key: key,
                    timeout: timeoutSeconds,
                    preferredPeripheralName: preferredPeripheralName
                )
                print("button \(btProfileTargetLabel(target)) slot=\(slot) key=\(hexString(key))")
                print(describeBTProfileButtonRead(key: key, payload: result.payload, notifies: result.notifies))
            }
        }
    }

    private static func createBTProfileTarget(
        bridge: ProbeBridge,
        preferredPeripheralName: String?,
        timeoutSeconds: TimeInterval,
        target: UInt8,
        guid: UUID,
        profileName: String,
        owner: String,
        values: [Int],
        active: Int,
        brightness: UInt8
    ) async throws {
        try await writeBTProfileStep(
            bridge: bridge,
            preferredPeripheralName: preferredPeripheralName,
            timeoutSeconds: timeoutSeconds,
            label: "clear-target",
            key: BLEVendorProtocol.Key.profileTargetDelete(target: target).bytes,
            payload: []
        )
        try await writeBTProfileStep(
            bridge: bridge,
            preferredPeripheralName: preferredPeripheralName,
            timeoutSeconds: timeoutSeconds,
            label: "prepare-1",
            key: BLEVendorProtocol.Key.profileTargetPrepare(target: target).bytes,
            payload: [0x00]
        )

        let statusKey = BLEVendorProtocol.Key.profileTargetStatusGet(target: target).bytes
        let status = try await bridge.rawRead(
            key: statusKey,
            timeout: timeoutSeconds,
            preferredPeripheralName: preferredPeripheralName
        )
        print("step=status key=\(hexString(statusKey)) payload=\(status.payload.map { hexString(Array($0)) } ?? "nil")")

        try await writeBTProfileStep(
            bridge: bridge,
            preferredPeripheralName: preferredPeripheralName,
            timeoutSeconds: timeoutSeconds,
            label: "apply",
            key: BLEVendorProtocol.Key.profileTargetApply(target: target).bytes,
            payload: [0x00]
        )
        try await writeBTProfileStep(
            bridge: bridge,
            preferredPeripheralName: preferredPeripheralName,
            timeoutSeconds: timeoutSeconds,
            label: "commit-before-metadata",
            key: BLEVendorProtocol.Key.profileTargetCommit(target: target).bytes,
            payload: []
        )

        let metadataKey = BLEVendorProtocol.Key.profileMetadataSet(target: target).bytes
        for chunk in try buildBTProfileMetadataChunks(guid: guid, profileName: profileName, owner: owner) {
            let offset = Int(chunk[2]) | (Int(chunk[3]) << 8)
            try await writeBTProfileStep(
                bridge: bridge,
                preferredPeripheralName: preferredPeripheralName,
                timeoutSeconds: timeoutSeconds,
                label: String(format: "metadata-0x%04x", offset),
                key: metadataKey,
                payload: chunk
            )
        }

        let clampedActive = max(0, min(values.count - 1, active))
        let activeValue = UInt16(max(100, min(30_000, values[clampedActive])))
        try await writeBTProfileStep(
            bridge: bridge,
            preferredPeripheralName: preferredPeripheralName,
            timeoutSeconds: timeoutSeconds,
            label: "stored-dpi-scalar",
            key: BLEVendorProtocol.Key.storedDpiScalarSet(target: target).bytes,
            payload: [
                UInt8(activeValue & 0xFF),
                UInt8((activeValue >> 8) & 0xFF),
                UInt8(activeValue & 0xFF),
                UInt8((activeValue >> 8) & 0xFF),
                0x00,
                0x00,
            ]
        )

        let dpiPayload = Array(BLEVendorProtocol.buildDpiStagePayload(
            active: clampedActive,
            count: values.count,
            slots: values,
            marker: 0x00,
            stageIDs: [0x01, 0x02, 0x03, 0x04, 0x05]
        ))
        try await writeBTProfileStep(
            bridge: bridge,
            preferredPeripheralName: preferredPeripheralName,
            timeoutSeconds: timeoutSeconds,
            label: "stored-dpi-stages",
            key: BLEVendorProtocol.Key.storedDpiStagesSet(target: target).bytes,
            payload: dpiPayload
        )
        try await writeBTProfileStep(
            bridge: bridge,
            preferredPeripheralName: preferredPeripheralName,
            timeoutSeconds: timeoutSeconds,
            label: "prepare-2",
            key: BLEVendorProtocol.Key.profileTargetPrepare(target: target).bytes,
            payload: [0x00]
        )
        try await writeBTProfileStep(
            bridge: bridge,
            preferredPeripheralName: preferredPeripheralName,
            timeoutSeconds: timeoutSeconds,
            label: "stored-brightness",
            key: BLEVendorProtocol.Key.storedLightingBrightnessSet(target: target).bytes,
            payload: [brightness]
        )
    }

    private static func writeBTProfileStep(
        bridge: ProbeBridge,
        preferredPeripheralName: String?,
        timeoutSeconds: TimeInterval,
        label: String,
        key: [UInt8],
        payload: [UInt8]
    ) async throws {
        let result = try await bridge.rawWrite(
            key: key,
            payload: Data(payload),
            timeout: timeoutSeconds,
            preferredPeripheralName: preferredPeripheralName
        )
        print(
            "step=\(label) key=\(hexString(key)) payload[\(payload.count)]=\(hexString(payload)) " +
            "status=\(describeBTAckStatus(result.ack))"
        )
        guard result.ack?.status == 0x02 else {
            throw ProbeError.protocolError("BT profile step '\(label)' failed with status \(describeBTAckStatus(result.ack))")
        }
    }

    private static func buildBTProfileMetadataChunks(
        guid: UUID,
        profileName: String,
        owner: String
    ) throws -> [[UInt8]] {
        let profileNameBytes = try asciiBytes(profileName, maxLength: 0x74 - 0x10, fieldName: "--profile-name")
        let ownerBytes = try asciiBytes(owner, maxLength: 64, fieldName: "--owner")
        guard ownerBytes.count == 64 else {
            throw ProbeError.usage("--owner must be exactly 64 ASCII bytes")
        }

        var metadata = [UInt8](repeating: 0x00, count: 0xFA)
        writeBytes(windowsGUIDBytes(guid), into: &metadata, at: 0x00)
        writeBytes(profileNameBytes, into: &metadata, at: 0x10)
        writeBytes(ownerBytes, into: &metadata, at: 0x74)

        let chunks: [(offset: Int, length: Int)] = [
            (0x0000, 0x4C),
            (0x004C, 0x4C),
            (0x0098, 0x4C),
            (0x00E4, 0x16),
        ]
        return chunks.map { chunk in
            [
                UInt8(metadata.count & 0xFF),
                UInt8((metadata.count >> 8) & 0xFF),
                UInt8(chunk.offset & 0xFF),
                UInt8((chunk.offset >> 8) & 0xFF),
            ] + Array(metadata[chunk.offset..<(chunk.offset + chunk.length)])
        }
    }

    private static func windowsGUIDBytes(_ uuid: UUID) -> [UInt8] {
        let raw = uuid.uuid
        let bytes = [
            raw.0, raw.1, raw.2, raw.3,
            raw.4, raw.5,
            raw.6, raw.7,
            raw.8, raw.9, raw.10, raw.11, raw.12, raw.13, raw.14, raw.15,
        ]
        return [
            bytes[3], bytes[2], bytes[1], bytes[0],
            bytes[5], bytes[4],
            bytes[7], bytes[6],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15],
        ]
    }

    private static func writeBytes(_ bytes: [UInt8], into target: inout [UInt8], at offset: Int) {
        for (index, byte) in bytes.enumerated() where offset + index < target.count {
            target[offset + index] = byte
        }
    }

    private static func readBTProfileDPI(
        bridge: ProbeBridge,
        preferredPeripheralName: String?,
        timeoutSeconds: TimeInterval,
        target: UInt8
    ) async throws -> BTProfileDPIRead {
        let scalarResult = try await bridge.rawRead(
            key: BLEVendorProtocol.Key.dpiScalarGet(target: target).bytes,
            timeout: timeoutSeconds,
            preferredPeripheralName: preferredPeripheralName
        )
        let pairListResult = try await bridge.rawRead(
            key: BLEVendorProtocol.Key.dpiPairListGet(target: target).bytes,
            timeout: timeoutSeconds,
            preferredPeripheralName: preferredPeripheralName
        )
        let tokenResult = try await bridge.rawRead(
            key: BLEVendorProtocol.Key.dpiStageTokenGet(target: target).bytes,
            timeout: timeoutSeconds,
            preferredPeripheralName: preferredPeripheralName
        )

        return BTProfileDPIRead(
            target: target,
            scalarRaw: scalarResult.payload,
            scalar: scalarResult.payload.flatMap(BLEVendorProtocol.parseDpiScalarPair),
            pairListRaw: pairListResult.payload,
            pairs: pairListResult.payload.flatMap(BLEVendorProtocol.parseDpiPairList) ?? [],
            tokenRaw: tokenResult.payload
        )
    }

    private static func readBTProfileLightingLEDIDs(
        bridge: ProbeBridge,
        preferredPeripheralName: String?,
        timeoutSeconds: TimeInterval
    ) async throws -> [UInt8] {
        let key = BLEVendorProtocol.Key.lightingZonesGet.bytes
        let result = try await bridge.rawRead(
            key: key,
            timeout: timeoutSeconds,
            preferredPeripheralName: preferredPeripheralName
        )
        return result.payload.flatMap(BLEVendorProtocol.parseLightingLEDIDs) ?? []
    }

    private static func readBTProfileLighting(
        bridge: ProbeBridge,
        preferredPeripheralName: String?,
        timeoutSeconds: TimeInterval,
        target: UInt8,
        ledID: UInt8
    ) async throws -> BTProfileLightingRead {
        let brightnessResult = try await bridge.rawRead(
            key: BLEVendorProtocol.Key.profileLightingBrightnessGet(target: target, ledID: ledID).bytes,
            timeout: timeoutSeconds,
            preferredPeripheralName: preferredPeripheralName
        )
        let stateResult = try await bridge.rawRead(
            key: BLEVendorProtocol.Key.profileLightingZoneStateGet(target: target, ledID: ledID).bytes,
            timeout: timeoutSeconds,
            preferredPeripheralName: preferredPeripheralName
        )
        let brightness = brightnessResult.payload.flatMap { payload in
            payload.count == 1 ? payload.first : nil
        }
        return BTProfileLightingRead(
            target: target,
            ledID: ledID,
            brightnessRaw: brightnessResult.payload,
            brightness: brightness,
            stateRaw: stateResult.payload,
            color: stateResult.payload.flatMap(BLEVendorProtocol.parseV3ProLightingZoneStatePayload)
        )
    }

    private static func describeBTProfileLightingRead(_ read: BTProfileLightingRead) -> String {
        let brightness = read.brightness.map { String($0) } ?? "nil"
        let color = read.color.map { String(format: "%02x%02x%02x", $0.r, $0.g, $0.b) } ?? "unparsed"
        return
            "lighting \(btProfileTargetLabel(read.target)) " +
            "led=0x\(String(format: "%02x", read.ledID)) " +
            "brightness=\(brightness) " +
            "rawBrightness=\(read.brightnessRaw.map { hexString(Array($0)) } ?? "nil") " +
            "color=\(color) " +
            "rawState=\(read.stateRaw.map { hexString(Array($0)) } ?? "nil")"
    }

    private static func describeBTProfileDPIRead(_ read: BTProfileDPIRead) -> String {
        let scalar = read.scalar.map { "\($0.x)x\($0.y)" } ?? "nil"
        let pairs = read.pairs.isEmpty ? "nil" : describeDpiPairs(read.pairs)
        let token = read.tokenRaw.flatMap(\.first).map { String(format: "0x%02x", $0) } ?? "nil"
        return
            "target \(btProfileTargetLabel(read.target)) " +
            "scalar=\(scalar) stages=\(pairs) token=\(token) " +
            "rawScalar=\(read.scalarRaw.map { hexString(Array($0)) } ?? "nil") " +
            "rawStages=\(read.pairListRaw.map { hexString(Array($0)) } ?? "nil") " +
            "rawToken=\(read.tokenRaw.map { hexString(Array($0)) } ?? "nil")"
    }

    private static func describeBTProfileButtonRead(
        key: [UInt8],
        payload: Data?,
        notifies: [Data]
    ) -> String {
        let raw = bestEffortBTButtonPayload(
            payload: payload,
            notifies: notifies,
            slot: key.count > 3 ? key[3] : 0x00
        )
        let rawDescription = raw.isEmpty ? "payload=nil" : "payload[\(raw.count)]=\(hexString(Array(raw)))"
        let decodedBlocks = decodeBTButtonReadFunctionBlocks(
            key: key,
            payload: raw,
            notifies: notifies
        )
        guard !decodedBlocks.isEmpty else {
            return rawDescription
        }

        let decodedDescription = decodedBlocks.map { decoded in
            "decoded-\(decoded.label)[\(decoded.block.count)]=\(hexString(decoded.block)) \(describeUSBFunctionBlock(decoded.block))"
        }.joined(separator: " ")
        return rawDescription + " " + decodedDescription
    }

    private static func describeBTAckStatus(_ ack: BLEVendorProtocol.NotifyHeader?) -> String {
        guard let ack else { return "nil" }
        return String(format: "0x%02x", ack.status)
    }

    private static func describeDpiPairs(_ pairs: [DpiPair]) -> String {
        "[" + pairs.map { "\($0.x)x\($0.y)" }.joined(separator: ",") + "]"
    }

    private static func btProfileTargetLabel(_ target: UInt8) -> String {
        switch target {
        case 0x00:
            return "hardware-active(target=0)"
        case 0x01:
            return "live-projection(target=1)"
        default:
            return "stored-slot=\(Int(target) - 1)(target=\(target))"
        }
    }

    private static func uniqueByteList(_ values: [UInt8]) -> [UInt8] {
        var seen: Set<UInt8> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func decodeBTButtonReadFunctionBlock(
        key: [UInt8],
        payload: Data,
        notifies: [Data]
    ) -> [UInt8]? {
        guard key.count == 4, key[0] == 0x08, key[1] == 0x84 else {
            return nil
        }
        if let decoded = decodeDuplicatedBTButtonReadFrame(bytes: Array(payload), slot: key[3]) {
            return decoded
        }
        for frame in notifies {
            if let decoded = decodeDuplicatedBTButtonReadFrame(bytes: Array(frame), slot: key[3]) {
                return decoded
            }
        }
        return nil
    }

    private struct BTButtonReadFunctionBlock {
        let label: String
        let block: [UInt8]
    }

    private static func decodeBTButtonReadFunctionBlocks(
        key: [UInt8],
        payload: Data,
        notifies: [Data]
    ) -> [BTButtonReadFunctionBlock] {
        if let duplicated = decodeBTButtonReadFunctionBlock(key: key, payload: payload, notifies: notifies) {
            return [BTButtonReadFunctionBlock(label: "function", block: duplicated)]
        }
        guard key.count == 4, key[0] == 0x08, key[1] == 0x84 else {
            return []
        }
        if let interleaved = decodeInterleavedBTButtonReadFrame(bytes: Array(payload), slot: key[3]) {
            return interleaved
        }
        for frame in notifies {
            if let interleaved = decodeInterleavedBTButtonReadFrame(bytes: Array(frame), slot: key[3]) {
                return interleaved
            }
        }
        return []
    }

    private static func decodeDuplicatedBTButtonReadFrame(bytes: [UInt8], slot: UInt8) -> [UInt8]? {
        guard bytes.count >= 16, bytes[0] == slot, bytes[1] == 0x00 else {
            return nil
        }

        var block: [UInt8] = []
        block.reserveCapacity(7)
        for index in stride(from: 2, through: 14, by: 2) {
            guard index + 1 < bytes.count, bytes[index] == bytes[index + 1] else {
                return nil
            }
            block.append(bytes[index])
        }
        return block
    }

    private static func decodeInterleavedBTButtonReadFrame(bytes: [UInt8], slot: UInt8) -> [BTButtonReadFunctionBlock]? {
        guard bytes.count >= 16, bytes[0] == slot, bytes[1] == 0x00 else {
            return nil
        }

        var evenLane: [UInt8] = []
        var oddLane: [UInt8] = []
        evenLane.reserveCapacity(7)
        oddLane.reserveCapacity(7)
        for index in stride(from: 2, through: 14, by: 2) {
            guard index + 1 < bytes.count else { return nil }
            evenLane.append(bytes[index])
            oddLane.append(bytes[index + 1])
        }
        guard evenLane != oddLane else { return nil }

        return [
            BTButtonReadFunctionBlock(label: "even-lane", block: evenLane),
            BTButtonReadFunctionBlock(label: "odd-lane", block: oddLane),
        ]
    }

    private struct BTProfileWatchSnapshot: Equatable {
        let buttonPayloadHex: String
        let buttonDescription: String
        let dpiPayloadHex: String
        let dpiActive: Int?
        let dpiCount: Int?
        let dpiValues: [Int]
        let dpiStageIDs: [UInt8]

        var signature: String {
            [
                buttonPayloadHex,
                dpiPayloadHex,
                dpiActive.map(String.init) ?? "nil",
                dpiCount.map(String.init) ?? "nil",
                dpiValues.map(String.init).joined(separator: ","),
                dpiStageIDs.map { String(format: "%02x", $0) }.joined(separator: ","),
            ].joined(separator: "|")
        }

        var summary: String {
            let dpiSummary: String
            if let dpiActive, let dpiCount {
                let stageIDs = dpiStageIDs.map { String(format: "%02x", $0) }.joined(separator: ",")
                dpiSummary = "dpi(active=\(dpiActive + 1)/\(dpiCount) values=\(dpiValues) stageIDs=[\(stageIDs)])"
            } else {
                dpiSummary = "dpi(payload=\(dpiPayloadHex))"
            }
            return "button=\(buttonDescription) \(dpiSummary)"
        }
    }

    private static func readBTProfileWatchSnapshot(
        bridge: ProbeBridge,
        preferredPeripheralName: String?,
        timeoutSeconds: TimeInterval,
        buttonSlot: UInt8
    ) async throws -> BTProfileWatchSnapshot {
        let buttonKey = BLEVendorProtocol.Key.buttonBind(slot: buttonSlot).bytes
        let buttonResult = try await bridge.rawRead(
            key: buttonKey,
            timeout: timeoutSeconds,
            preferredPeripheralName: preferredPeripheralName
        )
        let buttonPayload = bestEffortBTButtonPayload(
            payload: buttonResult.payload,
            notifies: buttonResult.notifies,
            slot: buttonSlot
        )
        let buttonPayloadHex = hexString(Array(buttonPayload))
        let buttonDescription = describeBTProfileWatchButtonPayload(
            slot: buttonSlot,
            payload: buttonPayload,
            notifies: buttonResult.notifies
        )

        let dpiResult = try await bridge.rawRead(
            key: BLEVendorProtocol.Key.dpiStagesGet.bytes,
            timeout: timeoutSeconds,
            preferredPeripheralName: preferredPeripheralName
        )
        let dpiPayload = dpiResult.payload ?? Data()
        let dpiPayloadHex = hexString(Array(dpiPayload))
        let dpiSnapshot = BLEVendorProtocol.parseDpiStageSnapshot(blob: dpiPayload)

        return BTProfileWatchSnapshot(
            buttonPayloadHex: buttonPayloadHex,
            buttonDescription: buttonDescription,
            dpiPayloadHex: dpiPayloadHex,
            dpiActive: dpiSnapshot?.active,
            dpiCount: dpiSnapshot?.count,
            dpiValues: dpiSnapshot.map { Array($0.slots.prefix($0.count)) } ?? [],
            dpiStageIDs: dpiSnapshot.map { Array($0.stageIDs.prefix($0.count)) } ?? []
        )
    }

    private static func describeBTProfileWatchButtonPayload(
        slot: UInt8,
        payload: Data,
        notifies: [Data]
    ) -> String {
        let key = BLEVendorProtocol.Key.buttonBind(slot: slot).bytes
        if let decoded = decodeBTButtonReadFunctionBlock(key: key, payload: payload, notifies: notifies) {
            return "decoded[\(hexString(decoded))]"
        }

        let bytes = Array(payload)
        if bytes.isEmpty {
            return "no-payload"
        }
        if bytes.count >= 9,
           bytes[0] == slot,
           bytes[1] == 0x00,
           bytes[2] == 0x02,
           bytes[3] == 0x01,
           bytes[4] == 0x02,
           bytes[5] == 0x01,
           bytes[6] == 0x00,
           bytes[7] == 0x04,
           bytes[8] == 0x45 {
            return "f12-variant[\(hexString(bytes))]"
        }

        return "raw[\(hexString(bytes))]"
    }

    private static func bestEffortBTButtonPayload(
        payload: Data?,
        notifies: [Data],
        slot: UInt8
    ) -> Data {
        if let payload, !payload.isEmpty {
            return payload
        }
        if let frame = notifies.first(where: { frame in
            frame.count >= 16 && frame.first == slot
        }) {
            return frame
        }
        return payload ?? Data()
    }

    private static func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private static func describeBTNotifyFrames(_ frames: [Data]) -> String {
        if frames.isEmpty {
            return "notifies: none"
        }
        let lines = frames.enumerated().map { index, frame in
            let header = BLEVendorProtocol.NotifyHeader(data: frame)
            let headerDetail: String
            if let header {
                headerDetail = " req=0x\(String(format: "%02x", header.req)) status=0x\(String(format: "%02x", header.status)) len=\(header.payloadLength)"
            } else {
                headerDetail = ""
            }
            return "notify[\(index)] len=\(frame.count)\(headerDetail) \(hexString(Array(frame)))"
        }
        return lines.joined(separator: "\n")
    }

    private static func invalidUSBLightingZone(zoneID: String?, usb: USBProbeClient) -> ProbeError {
        let requested = zoneID ?? "all"
        return .usage("Invalid --zone '\(requested)' (available: \(usb.lightingZoneChoices().joined(separator: ",")))")
    }

    private static func invalidBTLightingZone(zoneID: String?, choices: [String]) -> ProbeError {
        let requested = zoneID ?? "all"
        return .usage("Invalid --zone '\(requested)' (available: \(choices.joined(separator: ",")))")
    }

    private static func describeUSBLightingReadResult(_ result: USBLightingReadResult) -> String {
        let brightness = result.brightness.map(String.init) ?? "read_failed"
        return "brightness zone=\(result.target.zoneID) label=\"\(result.target.zoneLabel)\" led=0x\(String(format: "%02x", result.target.ledID)) value=\(brightness)"
    }

    private static func describeUSBLightingWriteResult(_ result: USBLightingWriteResult, operation: String) -> String {
        let hex = result.args.map { String(format: "%02x", $0) }.joined(separator: " ")
        let status = result.succeeded ? "ok" : "error"
        return "write-\(operation) zone=\(result.target.zoneID) label=\"\(result.target.zoneLabel)\" led=0x\(String(format: "%02x", result.target.ledID)) args=\(hex) status=\(status)"
    }

    private static func hexLEDIDList(_ ledIDs: [UInt8]) -> String {
        ledIDs.map { String(format: "0x%02x", $0) }.joined(separator: ",")
    }

    private static func describeBTLightingTarget(_ target: USBLightingTargetDescriptor) -> String {
        "zone id=\(target.zoneID) label=\"\(target.zoneLabel)\" ledIDs=[0x\(String(format: "%02x", target.ledID))]"
    }

    private static func describeBTLightingReadResult(_ result: BTLightingReadResult) -> String {
        let brightness = result.brightness.map(String.init) ?? "read_failed"
        let color = result.color.map { color in
            String(format: "%02x%02x%02x", color.r, color.g, color.b)
        } ?? "read_failed"
        return "lighting zone=\(result.target.zoneID) label=\"\(result.target.zoneLabel)\" led=0x\(String(format: "%02x", result.target.ledID)) brightness=\(brightness) color=\(color)"
    }

    private static func describeBTLightingWriteResult(_ result: BTLightingWriteResult, operation: String) -> String {
        let key = result.key.map { String(format: "%02x", $0) }.joined(separator: " ")
        let payload = result.payload.map { String(format: "%02x", $0) }.joined(separator: " ")
        let status = result.succeeded ? "ok" : "error"
        return "write-\(operation) zone=\(result.target.zoneID) label=\"\(result.target.zoneLabel)\" led=0x\(String(format: "%02x", result.target.ledID)) key=\(key) payload=\(payload) status=\(status)"
    }
}

do {
    try await OpenSnekProbe.run()
    Foundation.exit(EXIT_SUCCESS)
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    Foundation.exit(EXIT_FAILURE)
}
