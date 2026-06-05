import Command
import FileSystem
import Foundation
import Mockable
import Path
import SwifterPMCore
import TSCUtility
import TuistConstants
import TuistEnvironment
import TuistLogging

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

protocol SwifterPMResolving: Sendable {
    func resolveDependencies(_ request: SwifterPMResolutionRequest) async throws
    func updateDependencies(_ request: SwifterPMResolutionRequest) async throws
}

extension SwifterPM: SwifterPMResolving {
    func resolveDependencies(_ request: SwifterPMResolutionRequest) async throws {
        _ = try await resolve(request)
    }

    func updateDependencies(_ request: SwifterPMResolutionRequest) async throws {
        _ = try await update(request)
    }
}

public enum SwiftPackageManagerControllerError: FatalError, Equatable {
    case missingSwifterPMArgumentValue(String)
    case unsupportedSwifterPMArguments([String])
    case conflictingSCMToRegistryTransformationArguments

    public var type: ErrorType {
        .abort
    }

    public var description: String {
        switch self {
        case let .missingSwifterPMArgumentValue(argument):
            return "The SwifterPM argument \(argument) requires a value."
        case let .unsupportedSwifterPMArguments(arguments):
            return "The following Swift Package Manager arguments are not supported by SwifterPM: \(arguments.joined(separator: ", "))"
        case .conflictingSCMToRegistryTransformationArguments:
            return "The source-control to registry transformation arguments conflict."
        }
    }
}

public struct SwiftPackageManagerController: SwiftPackageManagerControlling {
    private let fileSystem: FileSysteming
    private let commandRunner: () -> CommandRunning
    private let swifterPM: SwifterPMResolving
    private let environmentVariables: @Sendable () -> [String: String]

    public init() {
        self.init(
            fileSystem: FileSystem(),
            commandRunner: { CommandRunner() },
            swifterPM: SwifterPM()
        )
    }

    init(
        fileSystem: FileSysteming,
        commandRunner: @escaping () -> CommandRunning,
        swifterPM: SwifterPMResolving = SwifterPM(),
        environmentVariables: @escaping @Sendable () -> [String: String] = { Environment.current.variables }
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
        self.swifterPM = swifterPM
        self.environmentVariables = environmentVariables
    }

    public func resolve(at path: AbsolutePath, arguments: [String], printOutput: Bool) async throws {
        if swifterPMIsEnabled {
            let request = try await swifterPMRequest(
                packagePath: path,
                arguments: arguments,
                printOutput: printOutput
            )
            try await swifterPM.resolveDependencies(request)
            return
        }

        let command = try await buildResolveOrUpdateCommand(
            packagePath: path,
            extraArguments: arguments + ["resolve"]
        )

        printOutput ?
            try await commandRunner().runAndPrint(arguments: command) :
            try await commandRunner().runAndWait(arguments: command)
    }

    public func update(at path: AbsolutePath, arguments: [String], printOutput: Bool) async throws {
        if swifterPMIsEnabled {
            let request = try await swifterPMRequest(
                packagePath: path,
                arguments: arguments,
                printOutput: printOutput
            )
            try await swifterPM.updateDependencies(request)
            return
        }

        let command = try await buildResolveOrUpdateCommand(
            packagePath: path,
            extraArguments: arguments + ["update"]
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

    private func buildSwiftPackageCommand(packagePath: AbsolutePath, extraArguments: [String]) -> [String] {
        [
            "swift",
            "package",
            "--package-path",
            packagePath.pathString,
        ]
            + extraArguments
    }

    private func buildResolveOrUpdateCommand(packagePath: AbsolutePath, extraArguments: [String]) async throws -> [String] {
        buildSwiftPackageCommand(packagePath: packagePath, extraArguments: extraArguments)
    }

    private var swifterPMIsEnabled: Bool {
        environmentVariables()[Constants.EnvironmentVariables.useSwifterPM] != nil
    }

    private func swifterPMRequest(
        packagePath: AbsolutePath,
        arguments: [String],
        printOutput: Bool
    ) async throws -> SwifterPMResolutionRequest {
        let options = try await SwifterPMOptions.parse(
            arguments,
            packagePath: packagePath,
            currentWorkingDirectory: try await Environment.current.currentWorkingDirectory()
        )

        return SwifterPMResolutionRequest(
            packageDirectory: options.packageDirectory,
            cacheDirectory: options.cacheDirectory,
            scratchDirectory: options.scratchDirectory,
            registryConfigurationPath: options.registryConfigurationPath,
            defaultRegistryURL: options.defaultRegistryURL,
            disableSandbox: options.disableSandbox,
            forceResolvedVersions: options.forceResolvedVersions,
            skipUpdate: options.skipUpdate,
            disablePackageInfoCache: options.disablePackageInfoCache,
            packageInfoCacheDirectory: options.packageInfoCacheDirectory,
            scmToRegistryTransformation: options.scmToRegistryTransformation,
            quiet: options.quiet || !printOutput
        )
    }
}

private struct SwifterPMOptions {
    var packageDirectory: Foundation.URL
    var cacheDirectory: Foundation.URL?
    var scratchDirectory: Foundation.URL?
    var registryConfigurationPath: Foundation.URL?
    var defaultRegistryURL: String?
    var disableSandbox = false
    var forceResolvedVersions = false
    var skipUpdate = false
    var disablePackageInfoCache = false
    var packageInfoCacheDirectory: Foundation.URL?
    var scmToRegistryTransformation: SCMToRegistryTransformation = .disabled
    var quiet = false

    private enum ValueOption: String, CaseIterable {
        case packagePath = "--package-path"
        case cachePath = "--cache-path"
        case scratchPath = "--scratch-path"
        case buildPath = "--build-path"
        case configPath = "--config-path"
        case defaultRegistryURL = "--default-registry-url"
        case packageInfoCachePath = "--package-info-cache-path"
        case chdir = "--chdir"
    }

    static func parse(
        _ arguments: [String],
        packagePath: AbsolutePath,
        currentWorkingDirectory: AbsolutePath
    ) async throws -> SwifterPMOptions {
        var baseDirectory = Foundation.URL(fileURLWithPath: currentWorkingDirectory.pathString, isDirectory: true)
            .standardizedFileURL
        var rawPackagePath = packagePath.pathString
        var rawCachePath: String?
        var rawScratchPath: String?
        var rawBuildPath: String?
        var rawConfigPath: String?
        var rawPackageInfoCachePath: String?
        var defaultRegistryURL: String?
        var disableSandbox = false
        var forceResolvedVersions = false
        var skipUpdate = false
        var disablePackageInfoCache = false
        var quiet = false
        var replaceSCMWithRegistry = false
        var useRegistryIdentityForSCM = false
        var disableSCMToRegistryTransformation = false
        var unsupportedArguments: [String] = []

        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if let option = ValueOption.allCases.first(where: { argument == $0.rawValue }) {
                let nextIndex = arguments.index(after: index)
                guard nextIndex < arguments.endIndex else {
                    throw SwiftPackageManagerControllerError.missingSwifterPMArgumentValue(argument)
                }
                let value = arguments[nextIndex]
                switch option {
                case .packagePath:
                    rawPackagePath = value
                case .cachePath:
                    rawCachePath = value
                case .scratchPath:
                    rawScratchPath = value
                case .buildPath:
                    rawBuildPath = value
                case .configPath:
                    rawConfigPath = value
                case .defaultRegistryURL:
                    defaultRegistryURL = value
                case .packageInfoCachePath:
                    rawPackageInfoCachePath = value
                case .chdir:
                    baseDirectory = resolve(value, relativeTo: baseDirectory)
                }
                index = arguments.index(after: nextIndex)
                continue
            }

            if let (option, value) = valueOption(argument) {
                switch option {
                case .packagePath:
                    rawPackagePath = value
                case .cachePath:
                    rawCachePath = value
                case .scratchPath:
                    rawScratchPath = value
                case .buildPath:
                    rawBuildPath = value
                case .configPath:
                    rawConfigPath = value
                case .defaultRegistryURL:
                    defaultRegistryURL = value
                case .packageInfoCachePath:
                    rawPackageInfoCachePath = value
                case .chdir:
                    baseDirectory = resolve(value, relativeTo: baseDirectory)
                }
                index = arguments.index(after: index)
                continue
            }

            switch argument {
            case "--disable-sandbox":
                disableSandbox = true
            case "--skip-update":
                skipUpdate = true
            case "--force-resolved-versions", "--disable-automatic-resolution", "--only-use-versions-from-resolved-file":
                forceResolvedVersions = true
            case "--replace-scm-with-registry":
                replaceSCMWithRegistry = true
            case "--use-registry-identity-for-scm":
                useRegistryIdentityForSCM = true
            case "--disable-scm-to-registry-transformation":
                disableSCMToRegistryTransformation = true
            case "--disable-package-info-cache":
                disablePackageInfoCache = true
            case "--enable-dependency-cache", "--disable-dependency-cache":
                break
            case "-q", "--quiet":
                quiet = true
            default:
                unsupportedArguments.append(argument)
            }
            index = arguments.index(after: index)
        }

        guard unsupportedArguments.isEmpty else {
            throw SwiftPackageManagerControllerError.unsupportedSwifterPMArguments(unsupportedArguments)
        }

        let enabledTransformationFlags = [
            replaceSCMWithRegistry,
            useRegistryIdentityForSCM,
            disableSCMToRegistryTransformation,
        ].filter { $0 }.count
        guard enabledTransformationFlags <= 1 else {
            throw SwiftPackageManagerControllerError.conflictingSCMToRegistryTransformationArguments
        }

        let scmToRegistryTransformation: SCMToRegistryTransformation = if replaceSCMWithRegistry {
            .replaceSCMWithRegistry
        } else if useRegistryIdentityForSCM {
            .useRegistryIdentityForSCM
        } else {
            .disabled
        }

        return SwifterPMOptions(
            packageDirectory: resolve(rawPackagePath, relativeTo: baseDirectory),
            cacheDirectory: rawCachePath.map { resolve($0, relativeTo: baseDirectory) },
            scratchDirectory: (rawScratchPath ?? rawBuildPath).map { resolve($0, relativeTo: baseDirectory) },
            registryConfigurationPath: rawConfigPath.map { resolve($0, relativeTo: baseDirectory) },
            defaultRegistryURL: defaultRegistryURL,
            disableSandbox: disableSandbox,
            forceResolvedVersions: forceResolvedVersions,
            skipUpdate: skipUpdate,
            disablePackageInfoCache: disablePackageInfoCache,
            packageInfoCacheDirectory: rawPackageInfoCachePath.map { resolve($0, relativeTo: baseDirectory) },
            scmToRegistryTransformation: scmToRegistryTransformation,
            quiet: quiet
        )
    }

    private static func valueOption(_ argument: String) -> (ValueOption, String)? {
        for option in ValueOption.allCases {
            let prefix = "\(option.rawValue)="
            if argument.hasPrefix(prefix) {
                return (option, String(argument.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    private static func resolve(_ path: String, relativeTo baseDirectory: Foundation.URL) -> Foundation.URL {
        if path.hasPrefix("/") {
            return Foundation.URL(fileURLWithPath: path).standardizedFileURL
        }
        return baseDirectory.appendingPathComponent(path).standardizedFileURL
    }
}
