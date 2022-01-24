import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Carthage Controller Error

enum CarthageControllerError: FatalError, Equatable {
    /// Thrown when Carthage cannot be found in the environment.
    case carthageNotFound
    /// Thrown when version of Carthage cannot be determined.
    case unrecognizedCarthageVersion
    /// Thrown when version of Carthage installed in environment does not support XCFrameworks production.
    case xcframeworksProductionNotSupported(installedVersion: Version)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .carthageNotFound,
             .unrecognizedCarthageVersion,
             .xcframeworksProductionNotSupported:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case .carthageNotFound:
            return """
            Carthage was not found in the environment.
            It's possible that the tool is not installed or hasn't been exposed to your environment.
            """
        case .unrecognizedCarthageVersion:
            return """
            The version of Carthage cannot be determined.
            It's possible that the tool is not installed or hasn't been exposed to your environment.
            """
        case let .xcframeworksProductionNotSupported(installedVersion):
            return """
            The version of Carthage installed in your environment (\(installedVersion
                .description)) doesn't suppport production of XCFrameworks.
            You have to update the tool to at least 0.37.0 version.
            """
        }
    }
}

// MARK: - Carthage Controlling

/// Protocol that defines an interface to interact with the Carthage.
public protocol CarthageControlling {
    /// Returns true if Carthage is available in the environment.
    func canUseSystemCarthage() -> Bool

    /// Return version of Carthage that is available in the environment.
    func carthageVersion() throws -> Version

    /// Checkouts and builds the project's dependencies
    /// - Parameters:
    ///   - path: Directory where project's dependencies will be installed.
    ///   - platforms: The platforms to build for.
    ///   - printOutput: When true it prints the Carthage's ouput.
    func bootstrap(at path: AbsolutePath, platforms: Set<TuistGraph.Platform>, printOutput: Bool) throws

    /// Updates and rebuilds the project's dependencies
    /// - Parameters:
    ///   - path: Directory where project's dependencies will be installed.
    ///   - platforms: The platforms to build for.
    ///   - printOutput: When true it prints the Carthage's ouput.
    func update(at path: AbsolutePath, platforms: Set<TuistGraph.Platform>, printOutput: Bool) throws
}

// MARK: - Carthage Controller

public final class CarthageController: CarthageControlling {
    /// Shared instance.
    public static var shared: CarthageControlling = CarthageController()

    /// Cached response of `carthage version` command.
    @Atomic
    private var cachedCarthageVersion: Version?

    public func canUseSystemCarthage() -> Bool {
        do {
            _ = try System.shared.which("carthage")
            return true
        } catch {
            return false
        }
    }

    public func carthageVersion() throws -> Version {
        // Return cached value if available
        if let cached = cachedCarthageVersion {
            return cached
        }

        guard let output = try? System.shared.capture(["/usr/bin/env", "carthage", "version"]).spm_chomp() else {
            throw CarthageControllerError.carthageNotFound
        }

        guard let version = Version(string: output) else {
            throw CarthageControllerError.unrecognizedCarthageVersion
        }

        cachedCarthageVersion = version
        return version
    }

    public func bootstrap(at path: AbsolutePath, platforms: Set<TuistGraph.Platform>, printOutput: Bool) throws {
        guard try isXCFrameworksProductionSupported() else {
            throw CarthageControllerError.xcframeworksProductionNotSupported(installedVersion: try carthageVersion())
        }

        let command = buildCarthageCommand(path: path, platforms: platforms, subcommand: "bootstrap")

        printOutput ?
            try System.shared.runAndPrint(command) :
            try System.shared.run(command)
    }

    public func update(at path: AbsolutePath, platforms: Set<TuistGraph.Platform>, printOutput: Bool) throws {
        guard try isXCFrameworksProductionSupported() else {
            throw CarthageControllerError.xcframeworksProductionNotSupported(installedVersion: try carthageVersion())
        }

        let command = buildCarthageCommand(path: path, platforms: platforms, subcommand: "update")

        printOutput ?
            try System.shared.runAndPrint(command) :
            try System.shared.run(command)
    }

    // MARK: - Helpers

    private func buildCarthageCommand(
        path: AbsolutePath,
        platforms: Set<TuistGraph.Platform>,
        subcommand: String
    ) -> [String] {
        var commandComponents: [String] = [
            "carthage",
            subcommand,
            "--project-directory",
            path.pathString,
        ]

        if !platforms.isEmpty {
            commandComponents += [
                "--platform",
                platforms
                    .map(\.caseValue)
                    .sorted()
                    .joined(separator: ","),
            ]
        }

        commandComponents += [
            "--use-xcframeworks",
            "--no-use-binaries",
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ]

        return commandComponents
    }

    private func isXCFrameworksProductionSupported() throws -> Bool {
        // Carthage has supported XCFrameworks production since 0.37.0
        // More info here: https://github.com/Carthage/Carthage/releases/tag/0.37.0
        try carthageVersion() >= Version(0, 37, 0)
    }
}
