import Foundation
import IOKit.hid
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

/// Describes probe failures.
enum ProbeError: LocalizedError {
  case usage(String)
  case protocolError(String)
  case timeout

  var errorDescription: String? {
    switch self {
    case .usage(let text): return text
    case .protocolError(let text): return text
    case .timeout: return "Operation timed out"
    }
  }
}

/// Captures DPI state.
struct DpiSnapshot: Equatable {
  let active: Int
  let count: Int
  let slots: [Int]
  let stageIDs: [UInt8]
  let marker: UInt8

  var values: [Int] { Array(slots.prefix(count)) }
}

/// Stores USB lighting read result data.
struct USBLightingReadResult: Sendable {
  let target: USBLightingTargetDescriptor
  let brightness: Int?
}

/// Stores USB lighting write result data.
struct USBLightingWriteResult: Sendable {
  let target: USBLightingTargetDescriptor
  let args: [UInt8]
  let succeeded: Bool
}

/// Stores USB lighting custom frame result data.
struct USBLightingCustomFrameResult: Sendable {
  let args: [UInt8]
  let succeeded: Bool
}

/// Stores USB lighting concurrency operation stats data.
struct USBLightingConcurrencyOperationStats: Sendable {
  let attempts: Int
  let successes: Int
  let failures: Int
  let averageMs: Double
  let maxMs: Double
}

/// Stores USB lighting concurrency probe result data.
struct USBLightingConcurrencyProbeResult: Sendable {
  let mode: String
  let elapsedMs: Double
  let frameStats: USBLightingConcurrencyOperationStats
  let commandReadStats: USBLightingConcurrencyOperationStats
  let commandWriteStats: USBLightingConcurrencyOperationStats
}

/// Stores USB battery read result data.
struct USBBatteryReadResult: Sendable {
  let charging: Bool
  let rawLevel: UInt8
  let percent: Int
}

/// Stores BT lighting read result data.
struct BTLightingReadResult: Sendable {
  let target: USBLightingTargetDescriptor
  let brightness: Int?
  let color: RGBPatch?
}

/// Stores BT lighting write result data.
struct BTLightingWriteResult: Sendable {
  let target: USBLightingTargetDescriptor
  let key: [UInt8]
  let payload: [UInt8]
  let succeeded: Bool
}

/// Stores USB probe device candidate data.
struct USBProbeDeviceCandidate: @unchecked Sendable {
  let index: Int
  let device: IOHIDDevice
  let devicePointer: UInt
  let deviceID: String
  let productID: Int
  let productName: String
  let locationID: Int
  let usagePage: Int
  let usage: Int
  let maxInputReportSize: Int
  let maxFeatureReportSize: Int
  let score: Int
  let passiveDescriptor: PassiveDPIInputDescriptor?

  var usageLabel: String {
    String(format: "0x%02x:0x%02x", usagePage, usage)
  }

  func describe() -> String {
    String(
      format:
        "candidate[%d] %@ pid=0x%04x loc=0x%08x usage=%@ input=%d feature=%d score=%d name=%@",
      index,
      deviceID,
      productID,
      locationID,
      usageLabel,
      maxInputReportSize,
      maxFeatureReportSize,
      score,
      productName
    )
  }
}

/// Stores BT HID probe device candidate data.
struct BTHIDProbeDeviceCandidate: @unchecked Sendable {
  let index: Int
  let device: IOHIDDevice
  let deviceID: String
  let vendorID: Int
  let productID: Int
  let productName: String
  let transport: String
  let locationID: Int
  let usagePage: Int
  let usage: Int
  let maxInputReportSize: Int
  let maxFeatureReportSize: Int
  let score: Int
  let passiveDescriptor: PassiveDPIInputDescriptor?

  var usageLabel: String {
    String(format: "0x%02x:0x%02x", usagePage, usage)
  }

  func describe() -> String {
    let format =
      "candidate[%d] %@ vid=0x%04x pid=0x%04x loc=0x%08x usage=%@ input=%d feature=%d "
      + "score=%d transport=\"%@\" name=%@"
    return String(
      format: format,
      index,
      deviceID,
      vendorID,
      productID,
      locationID,
      usageLabel,
      maxInputReportSize,
      maxFeatureReportSize,
      score,
      transport,
      productName
    )
  }
}

/// Stores USB probe candidate seed data.
private struct USBProbeCandidateSeed: @unchecked Sendable {
  let device: IOHIDDevice
  let deviceID: String
  let productID: Int
  let productName: String
  let locationID: Int
  let usagePage: Int
  let usage: Int
  let maxInputReportSize: Int
  let maxFeatureReportSize: Int
  let score: Int
  let passiveDescriptor: PassiveDPIInputDescriptor?
}

/// Stores BT HID probe candidate seed data.
private struct BTHIDProbeCandidateSeed: @unchecked Sendable {
  let device: IOHIDDevice
  let deviceID: String
  let vendorID: Int
  let productID: Int
  let productName: String
  let transport: String
  let locationID: Int
  let usagePage: Int
  let usage: Int
  let maxInputReportSize: Int
  let maxFeatureReportSize: Int
  let score: Int
  let passiveDescriptor: PassiveDPIInputDescriptor?
}

/// Stores USB profile DPI stages read result data.
struct USBProfileDPIStagesReadResult {
  let raw: [UInt8]
  let activeToken: UInt8
  let pairs: [DpiPair]
  let stageIDs: [UInt8]
}

/// Stores USB profile metadata read result data.
struct USBProfileMetadataReadResult {
  let chunks: [USBHIDProtocol.OnboardProfileMetadataChunk]
  let bytes: [UInt8]
  let metadata: USBHIDProtocol.OnboardProfileMetadata
}

/// Stores BT raw read result data.
struct BTRawReadResult {
  let req: UInt8
  let notifies: [Data]
  let payload: Data?
}

/// Stores BT raw write result data.
struct BTRawWriteResult {
  let req: UInt8
  let notifies: [Data]
  let ack: BLEVendorProtocol.NotifyHeader?
}

/// Carries USB raw command request data.
struct USBRawCommandRequest {
  let classID: UInt8
  let cmdID: UInt8
  let size: UInt8
  let args: [UInt8]
  let transactionID: UInt8
  let responseAttempts: Int
  let responseDelayUs: useconds_t
}

/// Carries USB button binding write request data.
struct USBButtonBindingWriteRequest {
  let profiles: [UInt8]
  let slot: Int
  let kind: String
  let hidKey: Int
  let turboEnabled: Bool
  let turboRate: Int
  let clutchDPI: Int?
}

func enumerateUSBProbeCandidates(preferredProductID: Int? = nil) throws -> (
  manager: IOHIDManager, candidates: [USBProbeDeviceCandidate]
) {
  let usbVID = 0x1532
  let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: usbVID] as CFDictionary)
  let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  guard openResult == kIOReturnSuccess else {
    throw ProbeError.protocolError("IOHIDManagerOpen failed (\(openResult))")
  }

  guard
    let rawSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
    !rawSet.isEmpty
  else {
    throw ProbeError.protocolError("No USB Razer HID device found")
  }

  var gathered: [USBProbeCandidateSeed] = []
  for candidate in rawSet {
    guard
      USBHIDSupport.intProperty(candidate, key: kIOHIDVendorIDKey as CFString) == usbVID,
      let product = USBHIDSupport.intProperty(candidate, key: kIOHIDProductIDKey as CFString)
    else { continue }
    if let preferredProductID, product != preferredProductID { continue }

    let transport =
      (USBHIDSupport.stringProperty(candidate, key: kIOHIDTransportKey as CFString) ?? "")
      .lowercased()
    if transport.contains("bluetooth") { continue }

    let locationID = USBHIDSupport.intProperty(candidate, key: kIOHIDLocationIDKey as CFString) ?? 0
    let deviceID = String(format: "%04x:%04x:%08x:usb", usbVID, product, locationID)
    let usagePage =
      USBHIDSupport.intProperty(candidate, key: kIOHIDPrimaryUsagePageKey as CFString) ?? 0
    let usage = USBHIDSupport.intProperty(candidate, key: kIOHIDPrimaryUsageKey as CFString) ?? 0
    let maxInputReportSize =
      USBHIDSupport.intProperty(candidate, key: kIOHIDMaxInputReportSizeKey as CFString) ?? 0
    let maxFeatureReportSize =
      USBHIDSupport.intProperty(candidate, key: kIOHIDMaxFeatureReportSizeKey as CFString) ?? 0
    let score = USBHIDSupport.handlePreferenceScore(device: candidate)
    let productName =
      USBHIDSupport.stringProperty(candidate, key: kIOHIDProductKey as CFString)
      ?? "Razer HID Device"
    let passiveDescriptor = DeviceProfiles.resolve(
      vendorID: usbVID, productID: product, transport: .usb)?.passiveDPIInput

    gathered.append(
      USBProbeCandidateSeed(
        device: candidate,
        deviceID: deviceID,
        productID: product,
        productName: productName,
        locationID: locationID,
        usagePage: usagePage,
        usage: usage,
        maxInputReportSize: maxInputReportSize,
        maxFeatureReportSize: maxFeatureReportSize,
        score: score,
        passiveDescriptor: passiveDescriptor
      ))
  }

  guard !gathered.isEmpty else {
    if let preferredProductID {
      throw ProbeError.protocolError(
        "No non-Bluetooth USB Razer HID interface found for pid 0x\(String(format: "%04x", preferredProductID))"
      )
    }
    throw ProbeError.protocolError("No non-Bluetooth USB Razer HID interface found")
  }

  let sorted = gathered.sorted { lhs, rhs in
    if lhs.score != rhs.score { return lhs.score > rhs.score }
    if lhs.usagePage != rhs.usagePage { return lhs.usagePage < rhs.usagePage }
    if lhs.usage != rhs.usage { return lhs.usage < rhs.usage }
    if lhs.maxInputReportSize != rhs.maxInputReportSize {
      return lhs.maxInputReportSize > rhs.maxInputReportSize
    }
    return lhs.maxFeatureReportSize > rhs.maxFeatureReportSize
  }

  let candidates = sorted.enumerated().map { index, candidate in
    USBProbeDeviceCandidate(
      index: index,
      device: candidate.device,
      devicePointer: UInt(bitPattern: Unmanaged.passUnretained(candidate.device).toOpaque()),
      deviceID: candidate.deviceID,
      productID: candidate.productID,
      productName: candidate.productName,
      locationID: candidate.locationID,
      usagePage: candidate.usagePage,
      usage: candidate.usage,
      maxInputReportSize: candidate.maxInputReportSize,
      maxFeatureReportSize: candidate.maxFeatureReportSize,
      score: candidate.score,
      passiveDescriptor: candidate.passiveDescriptor
    )
  }
  return (manager, candidates)
}

func enumerateBTHIDProfileCandidates(
  preferredProductID: Int? = 0x00AC,
  preferredPeripheralName: String? = nil
) throws -> (manager: IOHIDManager, candidates: [BTHIDProbeDeviceCandidate]) {
  let supportedVendorIDs = [0x068E, 0x1532]
  let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  let matching = supportedVendorIDs.map { [kIOHIDVendorIDKey: $0] as CFDictionary }
  IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
  let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  guard openResult == kIOReturnSuccess else {
    throw ProbeError.protocolError("IOHIDManagerOpen failed (\(openResult))")
  }

  guard
    let rawSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
    !rawSet.isEmpty
  else {
    throw ProbeError.protocolError("No Bluetooth Razer HID device found")
  }

  var gathered: [BTHIDProbeCandidateSeed] = []
  for candidate in rawSet {
    guard
      let vendorID = USBHIDSupport.intProperty(candidate, key: kIOHIDVendorIDKey as CFString),
      supportedVendorIDs.contains(vendorID),
      let productID = USBHIDSupport.intProperty(candidate, key: kIOHIDProductIDKey as CFString)
    else { continue }
    if let preferredProductID, productID != preferredProductID { continue }

    let transport =
      USBHIDSupport.stringProperty(candidate, key: kIOHIDTransportKey as CFString) ?? ""
    let transportLower = transport.lowercased()
    guard
      transportLower.contains("bluetooth") || transportLower.contains("ble") || vendorID == 0x068E
    else {
      continue
    }

    let productName =
      USBHIDSupport.stringProperty(candidate, key: kIOHIDProductKey as CFString)
      ?? "Razer Bluetooth HID Device"
    if let preferredPeripheralName,
      !BluetoothNameMatcher.looselyMatches(productName, preferredPeripheralName) {
      continue
    }

    let locationID = USBHIDSupport.intProperty(candidate, key: kIOHIDLocationIDKey as CFString) ?? 0
    let deviceID = String(format: "%04x:%04x:%08x:bluetooth-hid", vendorID, productID, locationID)
    let usagePage =
      USBHIDSupport.intProperty(candidate, key: kIOHIDPrimaryUsagePageKey as CFString) ?? 0
    let usage = USBHIDSupport.intProperty(candidate, key: kIOHIDPrimaryUsageKey as CFString) ?? 0
    let maxInputReportSize =
      USBHIDSupport.intProperty(candidate, key: kIOHIDMaxInputReportSizeKey as CFString) ?? 0
    let maxFeatureReportSize =
      USBHIDSupport.intProperty(candidate, key: kIOHIDMaxFeatureReportSizeKey as CFString) ?? 0
    let profile = DeviceProfiles.resolve(
      vendorID: vendorID, productID: productID, transport: .bluetooth)
    let descriptor = profile?.passiveDPIInput
    let descriptorScore: Int
    if let descriptor {
      descriptorScore =
        (usagePage == descriptor.usagePage ? 20 : 0) + (usage == descriptor.usage ? 20 : 0)
        + (maxInputReportSize >= descriptor.minInputReportSize ? 10 : 0)
        + (descriptor.maxFeatureReportSize == nil
          || maxFeatureReportSize == descriptor.maxFeatureReportSize ? 5 : 0)
    } else {
      descriptorScore = 0
    }
    let score = descriptorScore + max(0, min(20, maxInputReportSize))

    gathered.append(
      BTHIDProbeCandidateSeed(
        device: candidate,
        deviceID: deviceID,
        vendorID: vendorID,
        productID: productID,
        productName: productName,
        transport: transport,
        locationID: locationID,
        usagePage: usagePage,
        usage: usage,
        maxInputReportSize: maxInputReportSize,
        maxFeatureReportSize: maxFeatureReportSize,
        score: score,
        passiveDescriptor: descriptor
      ))
  }

  guard !gathered.isEmpty else {
    let productSuffix = preferredProductID.map { " for pid 0x\(String(format: "%04x", $0))" } ?? ""
    throw ProbeError.protocolError("No Bluetooth Razer HID interface found\(productSuffix)")
  }

  let sorted = gathered.sorted { lhs, rhs in
    if lhs.score != rhs.score { return lhs.score > rhs.score }
    if lhs.usagePage != rhs.usagePage { return lhs.usagePage < rhs.usagePage }
    if lhs.usage != rhs.usage { return lhs.usage < rhs.usage }
    if lhs.maxInputReportSize != rhs.maxInputReportSize {
      return lhs.maxInputReportSize > rhs.maxInputReportSize
    }
    return lhs.maxFeatureReportSize > rhs.maxFeatureReportSize
  }

  let candidates = sorted.enumerated().map { index, candidate in
    BTHIDProbeDeviceCandidate(
      index: index,
      device: candidate.device,
      deviceID: candidate.deviceID,
      vendorID: candidate.vendorID,
      productID: candidate.productID,
      productName: candidate.productName,
      transport: candidate.transport,
      locationID: candidate.locationID,
      usagePage: candidate.usagePage,
      usage: candidate.usage,
      maxInputReportSize: candidate.maxInputReportSize,
      maxFeatureReportSize: candidate.maxFeatureReportSize,
      score: candidate.score,
      passiveDescriptor: candidate.passiveDescriptor
    )
  }
  return (manager, candidates)
}
