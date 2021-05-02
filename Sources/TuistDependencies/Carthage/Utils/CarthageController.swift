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

    /// Error type.
    var type: ErrorType {
        switch self {
        case .carthageNotFound,
             .unrecognizedCarthageVersion:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case .carthageNotFound:
            return "Carthage was not found in the environment. It's possible that the tool is not installed or hasn't been exposed to your environment." // swiftlint:disable:this line_length
        case .unrecognizedCarthageVersion:
            return "Version of Carthage cannot be determined. It's possible that the tool is not installed or hasn't been exposed to your environment." // swiftlint:disable:this line_length
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

    /// Returns true if version of Carthage available in the environment supports producing XCFrameworks.
    func isXCFrameworksProductionSupported() throws -> Bool
    
    /// Checkouts and builds the project's dependencies
    /// - Parameters:
    ///   - path: Directory whose project's dependencies will be installed.
    ///   - platforms: The platforms to build for.
    ///   - options: The options for Carthage installation.
    func bootstrap(at path: AbsolutePath, platforms: Set<TuistGraph.Platform>, options: Set<CarthageDependencies.Options>) throws

    /// Updates and rebuilds the project's dependencies
    /// - Parameters:
    ///   - path: Directory whose project's dependencies will be installed.
    ///   - platforms: The platforms to build for.
    ///   - options: The options for Carthage installation.
    func update(at path: AbsolutePath, platforms: Set<TuistGraph.Platform>, options: Set<CarthageDependencies.Options>) throws
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

        guard let output = try? System.shared.capture("/usr/bin/env", "carthage", "version").spm_chomp() else {
            throw CarthageControllerError.carthageNotFound
        }

        guard let version = Version(string: output) else {
            throw CarthageControllerError.unrecognizedCarthageVersion
        }

        cachedCarthageVersion = version
        return version
    }

    public func isXCFrameworksProductionSupported() throws -> Bool {
        // Carthage has supported XCFrameworks production since 0.37.0
        // More info here: https://github.com/Carthage/Carthage/releases/tag/0.37.0
        try carthageVersion() >= Version(0, 37, 0)
    }

    public func bootstrap(at path: AbsolutePath, platforms: Set<TuistGraph.Platform>, options: Set<CarthageDependencies.Options>) throws {
        let command = buildCarthageCommand(path: path, platforms: platforms, options: options, subcommand: "bootstrap")
        try System.shared.run(command)
    }

    public func update(at path: AbsolutePath, platforms: Set<TuistGraph.Platform>, options: Set<CarthageDependencies.Options>) throws {
        let command = buildCarthageCommand(path: path, platforms: platforms, options: options, subcommand: "update")
        try System.shared.run(command)
    }

    // MARK: - Helpers

    private func buildCarthageCommand(
        path: AbsolutePath,
        platforms: Set<TuistGraph.Platform>,
        options: Set<CarthageDependencies.Options>,
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

        if !options.isEmpty {
            commandComponents += options
                .map { option in
                    switch option {
                    case .useXCFrameworks:
                        return "--use-xcframeworks"
                    case .noUseBinaries:
                        return "--no-use-binaries"
                    }
                }
                .sorted()
        }

        commandComponents += [
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ]

        return commandComponents
    }
}
