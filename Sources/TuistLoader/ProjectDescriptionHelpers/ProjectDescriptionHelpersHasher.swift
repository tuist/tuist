import Foundation
import Path
import TuistSupport

public protocol ProjectDescriptionHelpersHashing: AnyObject {
    /// Given the path to the directory that contains the helpers, it returns a hash that includes
    /// the hash of the files, the environment, as well as the versions of Swift and Tuist.
    /// - Parameter helpersDirectory: Path to the helpers directory.
    func hash(helpersDirectory: AbsolutePath) throws -> String

    /// Gets the prefix hash for the given helpers directory.
    /// This is useful to uniquely identify a helpers directory in the cache.
    /// - Parameter helpersDirectory: Path to the helpers directory.
    func prefixHash(helpersDirectory: AbsolutePath) -> String
}

public final class ProjectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing {
    /// Tuist version.
    private let tuistVersion: String
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let swiftVersionProvider: SwiftVersionProviding

    public init(
        tuistVersion: String = Constants.version,
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        swiftVersionProvider: SwiftVersionProviding = SwiftVersionProvider.shared
    ) {
        self.tuistVersion = tuistVersion
        self.machineEnvironment = machineEnvironment
        self.swiftVersionProvider = swiftVersionProvider
    }

    // MARK: - ProjectDescriptionHelpersHashing

    public func hash(helpersDirectory: AbsolutePath) throws -> String {
        let fileHashes = FileHandler.shared
            .glob(helpersDirectory, glob: "**/*.swift")
            .sorted()
            .compactMap { $0.sha256() }
            .compactMap { $0.compactMap { byte in String(format: "%02x", byte) }.joined() }
        let tuistEnvVariables = Environment.shared.manifestLoadingVariables.map { "\($0.key)=\($0.value)" }.sorted()
        let swiftVersion = try swiftVersionProvider.swiftVersion()
        let macosVersion = machineEnvironment.macOSVersion
        #if DEBUG
            let debug = true
        #else
            let debug = false
        #endif

        let identifiers = [macosVersion, swiftVersion, tuistVersion] + fileHashes + tuistEnvVariables + ["\(debug)"]

        return identifiers.joined(separator: "-").md5
    }

    public func prefixHash(helpersDirectory: AbsolutePath) -> String {
        let pathString = helpersDirectory.pathString
        let index = pathString.index(pathString.startIndex, offsetBy: 7)
        return String(helpersDirectory.pathString.md5[..<index])
    }
}
