import Foundation

public struct IssueReportDeviceEntry: Hashable, Sendable {
    public let title: String
    public let summary: String
    public let diagnostics: String

    public init(title: String, summary: String, diagnostics: String) {
        self.title = title
        self.summary = summary
        self.diagnostics = diagnostics
    }
}

public struct IssueReportAppInfo: Hashable, Sendable {
    public let appVersion: String
    public let build: String
    public let logLevel: String
    public let logPath: String

    public init(appVersion: String, build: String, logLevel: String, logPath: String) {
        self.appVersion = appVersion
        self.build = build
        self.logLevel = logLevel
        self.logPath = logPath
    }
}

public struct IssueReportStatus: Hashable, Sendable {
    public let selectedDevice: String?
    public let warning: String?
    public let error: String?
    public let generatedAt: Date

    public init(selectedDevice: String?, warning: String?, error: String?, generatedAt: Date = Date()) {
        self.selectedDevice = selectedDevice
        self.warning = warning
        self.error = error
        self.generatedAt = generatedAt
    }
}

public struct IssueReportContext: Hashable, Sendable {
    public let appInfo: IssueReportAppInfo
    public let status: IssueReportStatus
    public let devices: [IssueReportDeviceEntry]

    public init(
        appInfo: IssueReportAppInfo,
        status: IssueReportStatus,
        devices: [IssueReportDeviceEntry]
    ) {
        self.appInfo = appInfo
        self.status = status
        self.devices = devices
    }
}

public struct IssueReportFormatter {
    public static func format(_ context: IssueReportContext) -> String {
        var lines: [String] = []
        lines.append("## OpenSnek Diagnostics")
        lines.append("")
        lines.append("- Generated: \(iso8601(context.status.generatedAt))")
        lines.append("- App version: \(context.appInfo.appVersion)")
        lines.append("- Build: \(context.appInfo.build)")
        lines.append("- Log level: \(context.appInfo.logLevel)")
        lines.append("- Log file: `\(context.appInfo.logPath)`")
        lines.append("- Selected device: \(context.status.selectedDevice ?? "None")")
        lines.append("- Current warning: \(context.status.warning ?? "None")")
        lines.append("- Current error: \(context.status.error ?? "None")")
        lines.append("")

        lines.append("### Connected Devices")
        if context.devices.isEmpty {
            lines.append("_No devices were connected when this payload was generated._")
        } else {
            lines.append(contentsOf: context.devices.map { "- \($0.summary)" })
        }
        lines.append("")

        for entry in context.devices {
            lines.append("### Device Dump: \(entry.title)")
            lines.append("")
            lines.append("```text")
            lines.append(entry.diagnostics)
            lines.append("```")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
