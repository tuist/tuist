import Command
import FileSystem
import Foundation
import Mockable
import Path
import TSCUtility

/// Protocol that defines an interface to interact with the Swift Package Manager.
@Mockable
public protocol SwiftPackageManagerControlling {
    /// Resolves package dependencies.
    /// - Parameters:
    ///   - path: Directory where the `Package.swift` is defined.
    ///   - arguments: Additional arguments for `swift package resolve`.
    ///   - printOutput: When true it prints the Swift Package Manager's output.
    func resolve(at path: AbsolutePath, arguments: [String], printOutput: Bool) throws

    /// Updates package dependencies.
    /// - Parameters:
    ///   - path: Directory where the `Package.swift` is defined.
    ///   - arguments: Additional arguments for `swift package update`.
    ///   - printOutput: When true it prints the Swift Package Manager's output.
    func update(at path: AbsolutePath, arguments: [String], printOutput: Bool) throws

    /// Gets the tools version of the package at the given path
    /// - Parameter path: Directory where the `Package.swift` is defined.
    /// - Returns: Version of tools.
    func getToolsVersion(at path: AbsolutePath) throws -> Version

    /// Sets tools version of package to the given value.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    /// - Parameter version: Version of tools. When `nil` then the environment’s version will be set.
    func setToolsVersion(at path: AbsolutePath, to version: Version) throws

    /// Builds a release binary containing release binaries compatible with arm64 and x86.
    /// - Parameters:
    ///     - packagePath: Directory where the `Package.swift` is defined.
    ///     - product: Name of the product to be built.
    ///     - buildPath: Directory where the intermediary build products should be saved.
    ///     - outputPath: Directory where the fat binaries should be saved to.
    func buildFatReleaseBinary(
        packagePath: AbsolutePath,
        product: String,
        buildPath: AbsolutePath,
        outputPath: AbsolutePath
    ) async throws

    /// Logs in to the package registry
    /// - Parameters:
    ///     - token: Token to log in with.
    ///     - registryURL: The URL of the registry to use for logging in.
    func packageRegistryLogin(
        token: String,
        registryURL: Foundation.URL
    ) async throws

    /// Log out of the package registry
    /// - Parameters:
    ///     - registryURL: The URL of the registry to log out of.
    func packageRegistryLogout(
        registryURL: Foundation.URL
    ) async throws
}

public struct SwiftPackageManagerController: SwiftPackageManagerControlling {
    private let system: Systeming
    private let fileSystem: FileSysteming
    private let commandRunner: () -> CommandRunning

    public init() {
        self.init(
            system: System.shared,
            fileSystem: FileSystem(),
            commandRunner: { CommandRunner(logger: Logger.current) }
        )
    }

    init(
        system: Systeming,
        fileSystem: FileSysteming,
        commandRunner: @escaping () -> CommandRunning
    ) {
        self.system = system
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    public func resolve(at path: AbsolutePath, arguments: [String], printOutput: Bool) throws {
        let command = buildSwiftPackageCommand(
            packagePath: path,
            extraArguments: arguments + ["resolve"]
        )

        printOutput ?
            try system.runAndPrint(command) :
            try system.run(command)
    }

    public func update(at path: AbsolutePath, arguments: [String], printOutput: Bool) throws {
        let command = buildSwiftPackageCommand(
            packagePath: path,
            extraArguments: arguments + ["update"]
        )

        printOutput ?
            try system.runAndPrint(command) :
            try system.run(command)
    }

    public func setToolsVersion(at path: AbsolutePath, to version: Version) throws {
        let extraArguments = ["tools-version", "--set", "\(version.major).\(version.minor)"]

        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: extraArguments)

        try system.run(command)
    }

    public func getToolsVersion(at path: AbsolutePath) throws -> Version {
        let extraArguments = ["tools-version"]

        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: extraArguments)

        let rawVersion = try system.capture(command).trimmingCharacters(in: .whitespacesAndNewlines)
        return try Version(versionString: rawVersion)
    }

    public func buildFatReleaseBinary(
        packagePath: AbsolutePath,
        product: String,
        buildPath: AbsolutePath,
        outputPath: AbsolutePath
    ) async throws {
        let buildCommand: [String] = [
            "swift", "build",
            "--configuration", "release",
            "--disable-sandbox",
            "--package-path", packagePath.pathString,
            "--product", product,
            "--build-path", buildPath.pathString,
            "--triple",
        ]

        let arm64Target = "arm64-apple-macosx"
        let x64Target = "x86_64-apple-macosx"
        try system.run(
            buildCommand + [
                arm64Target,
            ]
        )
        try system.run(
            buildCommand + [
                x64Target,
            ]
        )

        if try await !fileSystem.exists(outputPath) {
            try await fileSystem.makeDirectory(at: outputPath)
        }

        try system.run([
            "lipo", "-create", "-output", outputPath.appending(component: product).pathString,
            buildPath.appending(components: arm64Target, "release", product).pathString,
            buildPath.appending(components: x64Target, "release", product).pathString,
        ])
    }

    public func packageRegistryLogin(
        token: String,
        registryURL: Foundation.URL
    ) async throws {
        _ = try await commandRunner().run(
            arguments: [
                "/usr/bin/swift",
                "package-registry",
                "login",
                registryURL.appending(path: "login").absoluteString,
                "--token",
                token,
                "--no-confirm",
            ]
        )
        .concatenatedString()
    }

    public func packageRegistryLogout(
        registryURL: Foundation.URL
    ) async throws {
        _ = try await commandRunner().run(
            arguments: [
                "/usr/bin/swift",
                "package-registry",
                "logout",
                registryURL.appending(path: "logout").absoluteString,
            ]
        )
        .concatenatedString()
    }

    // MARK: - Helpers

    private func buildSwiftPackageCommand(packagePath: AbsolutePath, extraArguments: [String]) -> [String] {
        [
            "swift",
            "package",
            "--package-path",
            packagePath.pathString,
        ]
            + extraArguments
    }
}
