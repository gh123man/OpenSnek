import Foundation
import IOKit.hid
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

actor ProbeBridge {
  private let vendor = BLEVendorTransportClient()
  private var reqID: UInt8 = 0x30

  private func nextReq() -> UInt8 {
    defer { reqID = reqID &+ 1 }
    return reqID
  }

  func connectedPeripherals() async -> [BLEVendorTransportClient.ConnectedPeripheralSummary]? {
    await vendor.connectedPeripheralSummaries()
  }

  func bluetoothLightingProfile(preferredPeripheralName: String?) async -> DeviceProfile? {
    if let preferredPeripheralName,
      let profile = DeviceProfiles.resolveBluetoothFallback(name: preferredPeripheralName) {
      return profile
    }

    let summaries = await connectedPeripherals() ?? []
    if let preferredPeripheralName,
      let summary = summaries.first(where: {
        BluetoothNameMatcher.looselyMatches($0.name, preferredPeripheralName)
      }) {
      return DeviceProfiles.resolveBluetoothFallback(name: summary.name)
    }

    return summaries.compactMap { DeviceProfiles.resolveBluetoothFallback(name: $0.name) }.first
  }

  func bluetoothLightingZoneChoices(preferredPeripheralName: String?) async -> [String] {
    guard
      let profile = await bluetoothLightingProfile(preferredPeripheralName: preferredPeripheralName)
    else {
      return ["all"]
    }
    let zoneIDs = profile.usbLightingZones.map(\.id)
    return zoneIDs.isEmpty ? ["all"] : ["all"] + zoneIDs
  }

  func bluetoothLightingTargets(
    preferredPeripheralName: String?,
    zoneID: String? = nil
  ) async throws -> [USBLightingTargetDescriptor]? {
    if let profile = await bluetoothLightingProfile(
      preferredPeripheralName: preferredPeripheralName) {
      return profile.lightingTargets(for: zoneID)
    }

    guard zoneID == nil else { return nil }
    let liveLEDIDs = try await bluetoothLightingLEDIDs(
      preferredPeripheralName: preferredPeripheralName)
    let resolvedLEDIDs = liveLEDIDs.isEmpty ? [0x01] : liveLEDIDs
    return resolvedLEDIDs.map { ledID in
      USBLightingTargetDescriptor(
        zoneID: String(format: "led_%02x", ledID),
        zoneLabel: String(format: "LED 0x%02X", ledID),
        ledID: ledID
      )
    }
  }

  func bluetoothLightingLEDIDs(preferredPeripheralName: String?) async throws -> [UInt8] {
    let result = try await rawRead(
      key: BLEVendorProtocol.Key.lightingZonesGet.bytes,
      timeout: 1.0,
      preferredPeripheralName: preferredPeripheralName
    )
    return BLEVendorProtocol.parseLightingLEDIDs(blob: result.payload ?? Data()) ?? []
  }

  func readBluetoothLighting(
    preferredPeripheralName: String?,
    zoneID: String? = nil
  ) async throws -> [BTLightingReadResult]? {
    guard
      let targets = try await bluetoothLightingTargets(
        preferredPeripheralName: preferredPeripheralName,
        zoneID: zoneID
      )
    else {
      return nil
    }

    let profile = await bluetoothLightingProfile(preferredPeripheralName: preferredPeripheralName)
    let usesZoneState = profile?.id == .basiliskV3Pro
    var results: [BTLightingReadResult] = []
    results.reserveCapacity(targets.count)

    for target in targets {
      let brightnessResult = try await rawRead(
        key: BLEVendorProtocol.Key.lightingBrightnessGet(ledID: target.ledID).bytes,
        timeout: 1.0,
        preferredPeripheralName: preferredPeripheralName
      )
      let brightness = brightnessResult.payload.flatMap { payload -> Int? in
        guard let value = payload.first else { return nil }
        return Int(value)
      }

      let color: RGBPatch?
      if usesZoneState {
        let colorResult = try await rawRead(
          key: BLEVendorProtocol.Key.lightingZoneStateGet(ledID: target.ledID).bytes,
          timeout: 1.0,
          preferredPeripheralName: preferredPeripheralName
        )
        color = colorResult.payload.flatMap(BLEVendorProtocol.parseV3ProLightingZoneStatePayload)
      } else {
        let colorResult = try await rawRead(
          key: BLEVendorProtocol.Key.lightingFrameGet.bytes,
          timeout: 1.0,
          preferredPeripheralName: preferredPeripheralName
        )
        color = colorResult.payload.flatMap { payload in
          guard payload.count >= 8, payload[0] == 0x04 else { return nil }
          return RGBPatch(r: Int(payload[5]), g: Int(payload[6]), b: Int(payload[7]))
        }
      }

      results.append(
        BTLightingReadResult(
          target: target,
          brightness: brightness,
          color: color
        )
      )
    }
    return results
  }

  func writeBluetoothLightingBrightness(
    value: Int,
    preferredPeripheralName: String?,
    zoneID: String? = nil
  ) async throws -> [BTLightingWriteResult]? {
    guard
      let targets = try await bluetoothLightingTargets(
        preferredPeripheralName: preferredPeripheralName,
        zoneID: zoneID
      )
    else {
      return nil
    }

    let clamped = UInt8(max(0, min(255, value)))
    var results: [BTLightingWriteResult] = []
    results.reserveCapacity(targets.count)
    for target in targets {
      let key = BLEVendorProtocol.Key.lightingBrightnessSet(ledID: target.ledID).bytes
      let result = try await rawWrite(
        key: key,
        payload: Data([clamped]),
        timeout: 1.2,
        preferredPeripheralName: preferredPeripheralName
      )
      results.append(
        BTLightingWriteResult(
          target: target,
          key: key,
          payload: [clamped],
          succeeded: result.ack?.status == 0x02
        )
      )
    }
    return results
  }

  func writeBluetoothLightingColor(
    color: RGBPatch,
    preferredPeripheralName: String?,
    zoneID: String? = nil
  ) async throws -> [BTLightingWriteResult]? {
    guard
      let targets = try await bluetoothLightingTargets(
        preferredPeripheralName: preferredPeripheralName,
        zoneID: zoneID
      )
    else {
      return nil
    }

    let profile = await bluetoothLightingProfile(preferredPeripheralName: preferredPeripheralName)
    let usesZoneState = profile?.id == .basiliskV3Pro
    let v3ProPayload = Array(
      BLEVendorProtocol.buildV3ProLightingZoneStatePayload(
        r: color.r,
        g: color.g,
        b: color.b
      ))
    let legacyPayload: [UInt8] = [
      0x04, 0x00, 0x00, 0x00,
      0x00,
      UInt8(max(0, min(255, color.r))),
      UInt8(max(0, min(255, color.g))),
      UInt8(max(0, min(255, color.b)))
    ]

    var results: [BTLightingWriteResult] = []
    results.reserveCapacity(targets.count)
    for target in targets {
      let key =
        usesZoneState
        ? BLEVendorProtocol.Key.lightingZoneStateSet(ledID: target.ledID).bytes
        : BLEVendorProtocol.Key.lightingFrameSet.bytes
      let payload = usesZoneState ? v3ProPayload : legacyPayload
      let result = try await rawWrite(
        key: key,
        payload: Data(payload),
        timeout: 1.2,
        preferredPeripheralName: preferredPeripheralName
      )
      results.append(
        BTLightingWriteResult(
          target: target,
          key: key,
          payload: payload,
          succeeded: result.ack?.status == 0x02
        )
      )
    }
    return results
  }

  func rawRead(
    key: [UInt8],
    timeout: TimeInterval,
    preferredPeripheralName: String? = nil
  ) async throws -> BTRawReadResult {
    guard key.count == 4 else {
      throw ProbeError.usage("BT raw read key must be exactly 4 bytes")
    }
    let req = nextReq()
    let header = BLEVendorProtocol.buildReadHeader(
      req: req,
      key: BLEVendorProtocol.Key(b0: key[0], b1: key[1], b2: key[2], b3: key[3])
    )
    let notifies = try await vendor.run(
      writes: [header],
      timeout: timeout,
      preferredPeripheralName: preferredPeripheralName
    )
    let payload = BLEVendorProtocol.parsePayloadFrames(notifies: notifies, req: req)
    return BTRawReadResult(req: req, notifies: notifies, payload: payload)
  }

  func rawWrite(
    key: [UInt8],
    payload: Data,
    timeout: TimeInterval,
    preferredPeripheralName: String? = nil
  ) async throws -> BTRawWriteResult {
    guard key.count == 4 else {
      throw ProbeError.usage("BT raw write key must be exactly 4 bytes")
    }
    let req = nextReq()
    let header = BLEVendorProtocol.buildWriteHeader(
      req: req,
      payloadLength: UInt8(max(0, min(255, payload.count))),
      key: BLEVendorProtocol.Key(b0: key[0], b1: key[1], b2: key[2], b3: key[3])
    )
    var writes: [Data] = [header]
    if !payload.isEmpty {
      var offset = 0
      while offset < payload.count {
        let nextOffset = min(offset + 20, payload.count)
        writes.append(payload.subdata(in: offset..<nextOffset))
        offset = nextOffset
      }
    }
    let notifies = try await vendor.run(
      writes: writes,
      timeout: timeout,
      preferredPeripheralName: preferredPeripheralName
    )
    let ack = notifies.compactMap { BLEVendorProtocol.NotifyHeader(data: $0) }.first(where: {
      $0.req == req
    })
    return BTRawWriteResult(req: req, notifies: notifies, ack: ack)
  }

  func readDpi() async throws -> DpiSnapshot {
    let req = nextReq()
    let header = BLEVendorProtocol.buildReadHeader(req: req, key: .dpiStagesGet)
    let notifies = try await vendor.run(writes: [header], timeout: 1.2)
    if let payload = BLEVendorProtocol.parsePayloadFrames(notifies: notifies, req: req),
      let parsed = BLEVendorProtocol.parseDpiStageSnapshot(blob: payload) {
      return DpiSnapshot(
        active: parsed.active,
        count: parsed.count,
        slots: parsed.slots,
        stageIDs: parsed.stageIDs,
        marker: parsed.marker
      )
    }
    throw ProbeError.protocolError("Failed to parse DPI payload")
  }

  func setDpi(active: Int, values: [Int]) async throws -> DpiSnapshot {
    let current = try await readDpi()
    let count = DeviceProfiles.clampDpiStageCount(values.count)
    let mergedSlots = BLEVendorProtocol.mergedStageSlots(
      currentSlots: current.slots,
      requestedCount: count,
      requestedValues: values
    )
    let expected = DpiSnapshot(
      active: max(0, min(count - 1, active)),
      count: count,
      slots: mergedSlots,
      stageIDs: current.stageIDs,
      marker: current.marker
    )
    let payload = BLEVendorProtocol.buildDpiStagePayload(
      active: expected.active,
      count: expected.count,
      slots: expected.slots,
      marker: expected.marker,
      stageIDs: expected.stageIDs
    )

    let req = nextReq()
    let header = BLEVendorProtocol.buildWriteHeader(
      req: req, payloadLength: 0x26, key: .dpiStagesSet)
    let notifies = try await vendor.run(
      writes: [header, payload.prefix(20), payload.suffix(from: 20)],
      timeout: 1.0
    )
    guard
      let ack = notifies.compactMap({ BLEVendorProtocol.NotifyHeader(data: $0) }).first(where: {
        $0.req == req
      }),
      ack.status == 0x02
    else {
      throw ProbeError.protocolError("DPI set did not return success ACK")
    }

    let readback = try await readDpi()
    if readback.active == expected.active && readback.values == expected.values {
      return readback
    }
    throw ProbeError.protocolError("Readback mismatch after DPI set")
  }
}
