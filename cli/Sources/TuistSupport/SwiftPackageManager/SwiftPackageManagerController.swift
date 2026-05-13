import Command
import FileSystem
import Foundation
import Logging
import Mockable
import Path
import TSCUtility
import TuistConstants
import TuistEnvironment

/// Protocol that defines an interface to interact with the Swift Package Manager.
@Mockable
public protocol SwiftPackageManagerControlling {
    /// Resolves package dependencies.
    /// - Parameters:
    ///   - path: Directory where the `Package.swift` is defined.
    ///   - arguments: Additional arguments for `swift package resolve`.
    ///   - printOutput: When true it prints the Swift Package Manager's output.
    func resolve(at path: AbsolutePath, arguments: [String], printOutput: Bool) async throws

    /// Updates package dependencies.
    /// - Parameters:
    ///   - path: Directory where the `Package.swift` is defined.
    ///   - arguments: Additional arguments for `swift package update`.
    ///   - printOutput: When true it prints the Swift Package Manager's output.
    func update(at path: AbsolutePath, arguments: [String], printOutput: Bool) async throws

    /// Gets the tools version of the package at the given path
    /// - Parameter path: Directory where the `Package.swift` is defined.
    /// - Returns: Version of tools.
    func getToolsVersion(at path: AbsolutePath) async throws -> Version

    /// Sets tools version of package to the given value.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    /// - Parameter version: Version of tools. When `nil` then the environment’s version will be set.
    func setToolsVersion(at path: AbsolutePath, to version: Version) async throws

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
    private let fileSystem: FileSysteming
    private let commandRunner: () -> CommandRunning
    private let environment: () -> [String: String]

    public init() {
        self.init(
            fileSystem: FileSystem(),
            commandRunner: { CommandRunner(logger: Logger.current) },
            environment: { Environment.current.variables }
        )
    }

    init(
        fileSystem: FileSysteming,
        commandRunner: @escaping () -> CommandRunning,
        environment: @escaping () -> [String: String] = { Environment.current.variables }
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
        self.environment = environment
    }

    public func resolve(at path: AbsolutePath, arguments: [String], printOutput: Bool) async throws {
        let command = buildPackageManagerCommand(
            packagePath: path,
            extraArguments: arguments,
            command: "resolve"
        )

        printOutput ?
            try await commandRunner().runAndPrint(arguments: command) :
            try await commandRunner().runAndWait(arguments: command)
    }

    public func update(at path: AbsolutePath, arguments: [String], printOutput: Bool) async throws {
        let command = buildPackageManagerCommand(
            packagePath: path,
            extraArguments: arguments,
            command: "update"
        )

        printOutput ?
            try await commandRunner().runAndPrint(arguments: command) :
            try await commandRunner().runAndWait(arguments: command)
    }

    public func setToolsVersion(at path: AbsolutePath, to version: Version) async throws {
        let extraArguments = ["tools-version", "--set", "\(version.major).\(version.minor)"]

        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: extraArguments)

        try await commandRunner().runAndWait(arguments: command)
    }

    public func getToolsVersion(at path: AbsolutePath) async throws -> Version {
        let extraArguments = ["tools-version"]

        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: extraArguments)

        let rawVersion = try await commandRunner().capture(arguments: command).trimmingCharacters(in: .whitespacesAndNewlines)
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
        try await commandRunner().runAndWait(
            arguments:
            buildCommand + [
                arm64Target,
            ]
        )
        try await commandRunner().runAndWait(
            arguments:
            buildCommand + [
                x64Target,
            ]
        )

        if try await !fileSystem.exists(outputPath) {
            try await fileSystem.makeDirectory(at: outputPath)
        }

        try await commandRunner().runAndWait(arguments: [
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

    private func buildPackageManagerCommand(
        packagePath: AbsolutePath,
        extraArguments: [String],
        command: String
    ) -> [String] {
        if usesFastPackageResolution {
            return buildSwifterPMCommand(
                packagePath: packagePath,
                extraArguments: extraArguments,
                command: command
            )
        } else {
            return buildSwiftPackageCommand(
                packagePath: packagePath,
                extraArguments: extraArguments + [command]
            )
        }
    }

    private func buildSwiftPackageCommand(packagePath: AbsolutePath, extraArguments: [String]) -> [String] {
        [
            "swift",
            "package",
            "--package-path",
            packagePath.pathString,
        ]
            + extraArguments
    }

    private func buildSwifterPMCommand(
        packagePath: AbsolutePath,
        extraArguments: [String],
        command: String
    ) -> [String] {
        [
            swifterPMExecutable(),
            "--package-path",
            packagePath.pathString,
        ]
            + swifterPMArguments(
                packagePath: packagePath,
                extraArguments: extraArguments,
                command: command
            )
            + [command]
    }

    private var usesFastPackageResolution: Bool {
        isTruthy(environment()[Constants.EnvironmentVariables.useFastPackageResolution])
    }

    private func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "TRUE", "yes", "YES"].contains(value)
    }

    private func swifterPMExecutable() -> String {
        let variables = environment()
        if let configuredPath = variables[Constants.EnvironmentVariables.fastPackageResolverPath], !configuredPath.isEmpty {
            return configuredPath
        }

        if let currentExecutablePath = Environment.current.currentExecutablePath() {
            let bundledPath = currentExecutablePath.parentDirectory.appending(component: "swifterpm")
            if FileManager.default.isExecutableFile(atPath: bundledPath.pathString) {
                return bundledPath.pathString
            }
        }

        return "swifterpm"
    }

    private func swifterPMArguments(
        packagePath: AbsolutePath,
        extraArguments: [String],
        command: String
    ) -> [String] {
        let arguments = extraArguments.filter { argument in
            !Self.unsupportedSwifterPMArguments.contains(argument)
        }

        guard command == "resolve",
              !arguments.contains("--force-resolved-versions"),
              !arguments.contains("--disable-automatic-resolution"),
              !arguments.contains("--only-use-versions-from-resolved-file"),
              FileManager.default
              .fileExists(atPath: packagePath.appending(component: Constants.SwiftPackageManager.packageResolvedName).pathString)
        else {
            return arguments
        }

        return arguments + ["--force-resolved-versions"]
    }

    private static let unsupportedSwifterPMArguments: Set<String> = [
        "--replace-scm-with-registry",
        "--disable-scm-to-registry-transformation",
    ]
}
