// swift-tools-version: 6.2
import PackageDescription

let longFunctionWarningMS = "200"
let swiftCompilerDiagnostics: [SwiftSetting] = [.unsafeFlags(["-Xfrontend", "-warn-long-function-bodies=\(longFunctionWarningMS)"])]
let swiftFormatBuildPlugins: [Target.PluginUsage] = [.plugin(name: "SwiftFormatBuildToolPlugin")]
let swiftLintBuildPlugins: [Target.PluginUsage] = [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
let swiftQualityBuildPlugins = swiftFormatBuildPlugins + swiftLintBuildPlugins

let package = Package(
    name: "OpenSnek", platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenSnekCore", targets: ["OpenSnekCore"]), .library(name: "OpenSnekProtocols", targets: ["OpenSnekProtocols"]), .library(name: "OpenSnekHardware", targets: ["OpenSnekHardware"]), .library(name: "OpenSnekAppSupport", targets: ["OpenSnekAppSupport"]),
        .executable(name: "OpenSnek", targets: ["OpenSnek"]), .executable(name: "OpenSnekProbe", targets: ["OpenSnekProbe"])
    ], dependencies: [.package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.63.3")],
    targets: [
        .target(name: "OpenSnekCore", path: "Sources/OpenSnekCore", swiftSettings: swiftCompilerDiagnostics, plugins: swiftQualityBuildPlugins),
        .target(name: "OpenSnekProtocols", dependencies: ["OpenSnekCore"], path: "Sources/OpenSnekProtocols", swiftSettings: swiftCompilerDiagnostics, plugins: swiftQualityBuildPlugins),
        .target(name: "OpenSnekHardware", dependencies: ["OpenSnekCore", "OpenSnekProtocols"], path: "Sources/OpenSnekHardware", swiftSettings: swiftCompilerDiagnostics, plugins: swiftQualityBuildPlugins),
        .target(name: "OpenSnekAppSupport", dependencies: ["OpenSnekCore", "OpenSnekHardware"], path: "Sources/OpenSnekAppSupport", swiftSettings: swiftCompilerDiagnostics, plugins: swiftQualityBuildPlugins),
        .executableTarget(name: "OpenSnek", dependencies: ["OpenSnekCore", "OpenSnekProtocols", "OpenSnekHardware", "OpenSnekAppSupport"], path: "Sources/OpenSnek", swiftSettings: swiftCompilerDiagnostics, plugins: swiftQualityBuildPlugins),
        .executableTarget(name: "OpenSnekProbe", dependencies: ["OpenSnekCore", "OpenSnekProtocols", "OpenSnekHardware"], path: "Sources/OpenSnekProbe", swiftSettings: swiftCompilerDiagnostics, plugins: swiftQualityBuildPlugins),
        .testTarget(name: "OpenSnekTests", dependencies: ["OpenSnek", "OpenSnekCore", "OpenSnekProtocols", "OpenSnekHardware", "OpenSnekAppSupport"], path: "Tests/OpenSnekTests", swiftSettings: swiftCompilerDiagnostics, plugins: swiftQualityBuildPlugins),
        .plugin(name: "SwiftFormatBuildToolPlugin", capability: .buildTool(), path: "Plugins/SwiftFormatBuildToolPlugin")
    ])
