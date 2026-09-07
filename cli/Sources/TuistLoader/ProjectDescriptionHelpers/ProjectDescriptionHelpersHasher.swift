import FileSystem
import Foundation
import Path
import TuistConstants
import TuistEnvironment
import TuistMacOSSDK
import TuistSupport

public protocol ProjectDescriptionHelpersHashing {
    /// Given the path to the directory that contains the helpers, it returns a hash that includes
    /// the hash of the files, the environment, as well as the versions of Swift and Tuist.
    /// - Parameter helpersDirectory: Path to the helpers directory.
    func hash(helpersDirectory: AbsolutePath) async throws -> String
}

public struct ProjectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing {
    /// Tuist version.
    private let tuistVersion: String
    private let fileSystem: FileSysteming
    #if os(macOS)
        private let machineEnvironment: MachineEnvironmentRetrieving
    #endif

    #if os(macOS)
        public init(
            tuistVersion: String = Constants.version,
            machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.tuistVersion = tuistVersion
            self.machineEnvironment = machineEnvironment
            self.fileSystem = fileSystem
        }
    #else
        public init(
            tuistVersion: String = Constants.version,
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.tuistVersion = tuistVersion
            self.fileSystem = fileSystem
        }
    #endif

    // MARK: - ProjectDescriptionHelpersHashing

    public func hash(helpersDirectory: AbsolutePath) async throws -> String {
        let fileHashes = try await fileSystem
            .glob(directory: helpersDirectory, include: ["**/*.swift"])
            .collect()
            .sorted()
            .compactMap { $0.sha256() }
            .compactMap { $0.compactMap { byte in String(format: "%02x", byte) }.joined() }
        let tuistEnvVariables = Environment.current.manifestLoadingVariables.map { "\($0.key)=\($0.value)" }.sorted()
        let swiftlangVersion = try await SwiftVersionProvider.current.swiftlangVersion()
        let platformVersions: [String]
        #if os(macOS)
            platformVersions = [
                machineEnvironment.macOSVersion,
                try await MacOSSDKVersionProvider.current.macOSSDKVersion(),
            ]
        #else
            platformVersions = [ProcessInfo.processInfo.operatingSystemVersionString]
        #endif
        #if DEBUG
            let debug = true
        #else
            let debug = false
        #endif

        let identifiers = platformVersions + [swiftlangVersion, tuistVersion] + fileHashes + tuistEnvVariables + ["\(debug)"]

        return identifiers.joined(separator: "-").md5
    }
}
