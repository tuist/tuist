import FileSystem
import Foundation
import Path
import TuistSupport

public protocol ProjectDescriptionHelpersHashing: AnyObject {
    /// Given the path to the directory that contains the helpers, it returns a hash that includes
    /// the hash of the files, the environment, as well as the versions of Swift and Tuist.
    /// - Parameter helpersDirectory: Path to the helpers directory.
    func hash(helpersDirectory: AbsolutePath) async throws -> String
}

public final class ProjectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing {
    /// Tuist version.
    private let tuistVersion: String
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let fileSystem: FileSysteming

    public init(
        tuistVersion: String = Constants.version,
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.tuistVersion = tuistVersion
        self.machineEnvironment = machineEnvironment
        self.fileSystem = fileSystem
    }

    // MARK: - ProjectDescriptionHelpersHashing

    public func hash(helpersDirectory: AbsolutePath) async throws -> String {
        let fileHashes = try await fileSystem
            .glob(directory: helpersDirectory, include: ["**/*.swift"])
            .collect()
            .sorted()
            .compactMap { $0.sha256() }
            .compactMap { $0.compactMap { byte in String(format: "%02x", byte) }.joined() }
        let tuistEnvVariables = Environment.current.manifestLoadingVariables.map { "\($0.key)=\($0.value)" }.sorted()
        let swiftVersion = try SwiftVersionProvider.current.swiftVersion()
        let macosVersion = machineEnvironment.macOSVersion
        #if DEBUG
            let debug = true
        #else
            let debug = false
        #endif

        let identifiers = [macosVersion, swiftVersion, tuistVersion] + fileHashes + tuistEnvVariables + ["\(debug)"]

        return identifiers.joined(separator: "-").md5
    }
}
