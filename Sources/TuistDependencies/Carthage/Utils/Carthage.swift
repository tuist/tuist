import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Carthage Command Generating

/// Protocol that defines an interface to interact with the Carthage.
public protocol Carthaging {
    /// Checkouts and builds the project's dependencies
    /// - Parameters:
    ///   - path: Directory whose project's dependencies will be installed.
    ///   - platforms: The platforms to build for.
    ///   - options: The options for Carthage installation.
    func bootstrap(at path: AbsolutePath, platforms: Set<Platform>, options: Set<CarthageDependencies.Options>) throws

    /// Updates and rebuilds the project's dependencies
    /// - Parameters:
    ///   - path: Directory whose project's dependencies will be installed.
    ///   - platforms: The platforms to build for.
    ///   - options: The options for Carthage installation.
    func update(at path: AbsolutePath, platforms: Set<Platform>, options: Set<CarthageDependencies.Options>) throws
}

// MARK: - Carthage Command Generator

public final class Carthage: Carthaging {
    public init() {}

    public func bootstrap(at path: AbsolutePath, platforms: Set<Platform>, options: Set<CarthageDependencies.Options>) throws {
        let command = buildCarthageCommand(path: path, platforms: platforms, options: options, subcommand: "bootstrap")
        try System.shared.run(command)
    }

    public func update(at path: AbsolutePath, platforms: Set<Platform>, options: Set<CarthageDependencies.Options>) throws {
        let command = buildCarthageCommand(path: path, platforms: platforms, options: options, subcommand: "update")
        try System.shared.run(command)
    }

    // MARK: - Helpers

    private func buildCarthageCommand(path: AbsolutePath, platforms: Set<Platform>, options: Set<CarthageDependencies.Options>, subcommand: String) -> [String] {
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
