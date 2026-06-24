import PackagePlugin

/// Runs the repository Swift format check before SwiftPM target builds.
@main struct SwiftFormatBuildToolPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let script = context.package.directoryURL.appending(path: "scripts/check_swift_format.sh")
        let outputDirectory = context.pluginWorkDirectoryURL.appending(path: target.name)
        return [.prebuildCommand(displayName: "Check Swift format (\(target.name))", executable: script, arguments: [target.directoryURL.path], outputFilesDirectory: outputDirectory)]
    }
}
