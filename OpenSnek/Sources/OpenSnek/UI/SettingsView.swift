import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppLog.levelDefaultsKey) private var logLevelRawValue = AppLog.currentLevel.rawValue

    private var selectedLevel: Binding<AppLogLevel> {
        Binding(
            get: { AppLogLevel(rawValue: logLevelRawValue) ?? AppLog.defaultLevel },
            set: {
                logLevelRawValue = $0.rawValue
                AppLog.updateLevel($0)
            }
        )
    }

    var body: some View {
        Form {
            Section("Logging") {
                Picker("Log level", selection: selectedLevel) {
                    ForEach(AppLogLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.menu)

                Text("Default is Warning. Raise this to Info or Debug before reproducing a bug if you need a more detailed log.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("Changing the level starts a fresh log file so the captured output matches the selected threshold.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(AppLog.path)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Button("Open Log File") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: AppLog.path))
                    }

                    Button("Open Log Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: AppLog.path)])
                    }

                    Button("Clear Log") {
                        AppLog.clear()
                    }
                }
            }

            Section("Bug Reports") {
                Text("Useful reports include the active protocol, the exact action that failed, whether it reproduced after reconnect, and a log captured at Info or Debug level.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
        .onAppear {
            AppLog.updateLevel(AppLogLevel(rawValue: logLevelRawValue) ?? AppLog.defaultLevel, resetLog: false)
        }
    }
}
