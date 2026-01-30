@_exported import TuistEnvironment
import Command
import Path

extension Environmenting {
    public var isLegacyModuleCacheEnabled: Bool {
        isVariableTruthy("TUIST_LEGACY_MODULE_CACHE")
    }
}

extension Environmenting {
    public func derivedDataDirectory() async throws -> Path.AbsolutePath {
        let commandRunner = CommandRunner()
        if let overrideLocation = try? await commandRunner.run(arguments: [
            "/usr/bin/defaults",
            "read",
            "com.apple.dt.Xcode IDEDerivedDataPathOverride",
        ], environment: variables).concatenatedString().chomp() {
            return try! AbsolutePath(validating: overrideLocation.chomp()) // swiftlint:disable:this force_try
        }

        if let customLocation = try? await commandRunner.run(arguments: [
            "/usr/bin/defaults",
            "read",
            "com.apple.dt.Xcode IDECustomDerivedDataLocation",
        ], environment: variables).concatenatedString().chomp() {
            return try! AbsolutePath(validating: customLocation.chomp()) // swiftlint:disable:this force_try
        }

        // Default location
        return homeDirectory
            .appending(try! RelativePath( // swiftlint:disable:this force_try
                validating: "Library/Developer/Xcode/DerivedData/"
            ))
    }

}

extension Environmenting {
    public func architecture() async throws -> MacArchitecture {
        return await MacArchitecture(
            rawValue: try CommandRunner()
                .run(arguments: ["/usr/bin/uname", "-m"], environment: variables).concatenatedString().chomp()
        )!
    }
}
