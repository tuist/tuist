import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Carthage Command Generating

public protocol CarthageCommandGenerating {
    /// Builds `Carthage` command.
    /// - Parameters:
    ///   - path: Directory whose project's dependencies will be installed.
    ///   - produceXCFrameworks: Indicates whether the `Carthage` produces XCFrameworks instead of universal frameworks.
    ///   - platforms: The platforms to build for.
    func command(path: AbsolutePath, produceXCFrameworks: Bool, platforms: Set<Platform>?) -> [String]
}

// MARK: - Carthage Command Generator

public final class CarthageCommandGenerator: CarthageCommandGenerating {
    public init() {}

    public func command(path: AbsolutePath, produceXCFrameworks: Bool, platforms: Set<Platform>?) -> [String] {
        var commandComponents: [String] = []
        commandComponents.append("carthage")
        commandComponents.append("bootstrap")

        // Project Directory

        commandComponents.append("--project-directory")
        commandComponents.append(path.pathString)

        // Platforms

        if let platforms = platforms, !platforms.isEmpty {
            commandComponents.append("--platform")
            commandComponents.append(
                platforms
                    .map(\.caseValue)
                    .sorted()
                    .joined(separator: ",")
            )
        }

        // Flags

        commandComponents.append("--use-netrc")
        commandComponents.append("--cache-builds")
        commandComponents.append("--new-resolver")

        if produceXCFrameworks {
            commandComponents.append("--use-xcframeworks")
        }

        // Return

        return commandComponents
    }
}
