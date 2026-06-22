import Foundation
import OpenSnekCore
import OpenSnekProtocols

extension OpenSnekProbe {
  static func invalidUSBLightingZone(zoneID: String?, usb: USBProbeClient) -> ProbeError {
    let requested = zoneID ?? "all"
    return .usage(
      "Invalid --zone '\(requested)' (available: \(usb.lightingZoneChoices().joined(separator: ",")))"
    )
  }

  static func invalidBTLightingZone(zoneID: String?, choices: [String]) -> ProbeError {
    let requested = zoneID ?? "all"
    return .usage("Invalid --zone '\(requested)' (available: \(choices.joined(separator: ",")))")
  }

  static func describeUSBLightingReadResult(_ result: USBLightingReadResult) -> String {
    let brightness = result.brightness.map(String.init) ?? "read_failed"
    return
      "brightness zone=\(result.target.zoneID) label=\"\(result.target.zoneLabel)\" led=0x\(String(format: "%02x", result.target.ledID)) value=\(brightness)"
  }

  static func describeUSBLightingWriteResult(
    _ result: USBLightingWriteResult, operation: String
  ) -> String {
    let hex = result.args.map { String(format: "%02x", $0) }.joined(separator: " ")
    let status = result.succeeded ? "ok" : "error"
    return
      "write-\(operation) zone=\(result.target.zoneID) label=\"\(result.target.zoneLabel)\" led=0x\(String(format: "%02x", result.target.ledID)) args=\(hex) status=\(status)"
  }

  static func describeUSBLightingConcurrencyResult(
    _ result: USBLightingConcurrencyProbeResult
  ) -> String {
    [
      "mode=\(result.mode)",
      String(format: "elapsed=%.1fms", result.elapsedMs),
      describeUSBLightingConcurrencyStats("frames", result.frameStats),
      describeUSBLightingConcurrencyStats("reads", result.commandReadStats),
      describeUSBLightingConcurrencyStats("writes", result.commandWriteStats)
    ].joined(separator: " ")
  }

  static func describeUSBLightingConcurrencyStats(
    _ label: String,
    _ stats: USBLightingConcurrencyOperationStats
  ) -> String {
    String(
      format: "%@=%d/%d fail=%d avg=%.2fms max=%.2fms",
      label,
      stats.successes,
      stats.attempts,
      stats.failures,
      stats.averageMs,
      stats.maxMs
    )
  }

  static func hexLEDIDList(_ ledIDs: [UInt8]) -> String {
    ledIDs.map { String(format: "0x%02x", $0) }.joined(separator: ",")
  }

  static func describeBTLightingTarget(_ target: USBLightingTargetDescriptor) -> String {
    "zone id=\(target.zoneID) label=\"\(target.zoneLabel)\" ledIDs=[0x\(String(format: "%02x", target.ledID))]"
  }

  static func describeBTLightingReadResult(_ result: BTLightingReadResult) -> String {
    let brightness = result.brightness.map(String.init) ?? "read_failed"
    let color =
      result.color.map { color in
        String(format: "%02x%02x%02x", color.r, color.g, color.b)
      } ?? "read_failed"
    return
      "lighting zone=\(result.target.zoneID) label=\"\(result.target.zoneLabel)\" led=0x\(String(format: "%02x", result.target.ledID)) brightness=\(brightness) color=\(color)"
  }

  static func describeBTLightingWriteResult(
    _ result: BTLightingWriteResult, operation: String
  ) -> String {
    let key = result.key.map { String(format: "%02x", $0) }.joined(separator: " ")
    let payload = result.payload.map { String(format: "%02x", $0) }.joined(separator: " ")
    let status = result.succeeded ? "ok" : "error"
    return
      "write-\(operation) zone=\(result.target.zoneID) label=\"\(result.target.zoneLabel)\" led=0x\(String(format: "%02x", result.target.ledID)) key=\(key) payload=\(payload) status=\(status)"
  }
}
