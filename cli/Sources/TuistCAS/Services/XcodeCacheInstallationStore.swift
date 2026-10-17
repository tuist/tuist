import FileSystem
import Foundation
import Mockable
import Path
import struct TSCUtility.Version
import TuistEnvironment

@Mockable
public protocol XcodeCacheInstallationStoring {
    func invalidate() async throws
    func record(pluginInstalled: Bool, xcodeBuildVersion: String?, tuistVersion: String) async throws
    func warning(developerDirectory: AbsolutePath?, xcodeBuildVersion: String?, tuistVersion: String) async -> String?
}

/// Describes the last successful setup, not the plugin images already loaded by Xcode.
public struct XcodeCacheInstallationStore: XcodeCacheInstallationStoring {
    struct Installation: Codable {
        let tuistVersion: String
        let launchAgentModifiedAt: Date
        let programModifiedAt: Date?
        let xcodeBuildVersion: String?
        let pluginInstalled: Bool
    }

    private struct LaunchAgent: Decodable {
        let program: AbsolutePath
        let environmentVariables: [String: String]?

        enum CodingKeys: String, CodingKey {
            case program = "Program"
            case environmentVariables = "EnvironmentVariables"
        }

        var developerDirectory: AbsolutePath? {
            guard let path = environmentVariables?["DEVELOPER_DIR"] else { return nil }
            return try? AbsolutePath(validating: path)
        }
    }

    private let fileSystem: FileSysteming
    private let directory: AbsolutePath
    private let launchAgentPath: AbsolutePath
    private var manifestPath: AbsolutePath { directory.appending(component: "cas-install.json") }
    private var installedPluginPath: AbsolutePath { directory.appending(component: "libtuist_cas_plugin.dylib") }

    public init(fileSystem: FileSysteming = FileSystem(), directory: AbsolutePath? = nil, launchAgentPath: AbsolutePath? = nil) {
        self.fileSystem = fileSystem
        self.directory = directory ?? Environment.current.casPluginInstallPath().parentDirectory
        self.launchAgentPath = launchAgentPath ?? Environment.current.homeDirectory
            .appending(components: "Library", "LaunchAgents", "tuist.cas-proxy.plist")
    }

    /// Invalidate before changing setup, so partial failures cannot leave a trusted old record.
    public func invalidate() async throws {
        try await fileSystem.remove(manifestPath)
    }

    public func record(pluginInstalled: Bool, xcodeBuildVersion: String?, tuistVersion: String) async throws {
        let agent: LaunchAgent = try await fileSystem.readPlistFile(at: launchAgentPath)
        guard let metadata = try await fileSystem.fileMetadata(at: launchAgentPath) else {
            throw XcodeCacheInstallationStoreError.invalidLaunchAgent
        }
        let installation = Installation(
            tuistVersion: tuistVersion,
            launchAgentModifiedAt: metadata.lastModificationDate,
            programModifiedAt: try await fileSystem.fileMetadata(at: agent.program)?.lastModificationDate,
            xcodeBuildVersion: xcodeBuildVersion,
            pluginInstalled: pluginInstalled
        )
        try await fileSystem.makeDirectory(at: directory)
        try await fileSystem.writeAsJSON(installation, at: manifestPath)
    }

    public func warning(developerDirectory: AbsolutePath?, xcodeBuildVersion: String?, tuistVersion: String) async -> String? {
        let hasAgent = (try? await fileSystem.exists(launchAgentPath)) == true
        let hasManifest = (try? await fileSystem.exists(manifestPath)) == true
        // Teardown keeps the stable plugin for existing projects. A plugin alone
        // is not evidence of an active or broken proxy setup.
        guard hasAgent || hasManifest else { return nil }
        guard hasAgent else {
            return message(["the cache proxy's LaunchAgent is missing"], tuistVersion: tuistVersion)
        }
        guard let agent: LaunchAgent = try? await fileSystem.readPlistFile(at: launchAgentPath) else {
            return message(["the cache proxy's LaunchAgent configuration could not be read"], tuistVersion: tuistVersion)
        }

        var reasons: [String] = []
        let programModifiedAt = try? await fileSystem.fileMetadata(at: agent.program)?.lastModificationDate
        if programModifiedAt == nil {
            reasons.append("the Tuist installation used to launch the cache proxy has been removed")
        }
        if let configuredDirectory = agent.developerDirectory, let developerDirectory, configuredDirectory != developerDirectory {
            reasons.append("the proxy was configured with a different Xcode (\(configuredDirectory.pathString))")
        }
        guard let installation = await currentInstallation(programModifiedAt: programModifiedAt) else {
            reasons.append("the cache setup version could not be verified (legacy or changed setup)")
            return message(reasons, tuistVersion: tuistVersion)
        }
        if let warning = versionWarning(installation.tuistVersion, currentVersion: tuistVersion) {
            reasons.append(warning)
        }
        if let xcodeBuildVersion, installation.xcodeBuildVersion != xcodeBuildVersion {
            reasons.append("the setup-time Xcode build differs or was not recorded")
        }
        if installation.pluginInstalled, (try? await fileSystem.exists(installedPluginPath)) != true {
            reasons.append("the installed cache plugin is missing")
        }
        return message(reasons, installation: installation, tuistVersion: tuistVersion)
    }

    private func currentInstallation(programModifiedAt: Date?) async -> Installation? {
        // Older CLIs do not invalidate the manifest. Both timestamps must still
        // match before its version can suppress an upgrade warning.
        guard let installation: Installation = try? await fileSystem.readJSONFile(at: manifestPath),
              let metadata = try? await fileSystem.fileMetadata(at: launchAgentPath),
              installation.launchAgentModifiedAt == metadata.lastModificationDate,
              installation.programModifiedAt == programModifiedAt
        else { return nil }
        return installation
    }

    private func message(_ reasons: [String], installation: Installation? = nil, tuistVersion: String) -> String? {
        guard !reasons.isEmpty else { return nil }
        let version = installation.map { " (last set up with Tuist \($0.tuistVersion); current Tuist \(tuistVersion))" } ?? ""
        return "Xcode Cache setup needs attention\(version): \(reasons.joined(separator: "; "))."
    }

    private func versionWarning(_ installedVersion: String, currentVersion: String) -> String? {
        guard let installed = try? Version(versionString: installedVersion),
              let current = try? Version(versionString: currentVersion)
        else { return "the cache setup's Tuist version could not be compared" }
        // An older checkout must not ask users to downgrade a known newer setup.
        return installed < current ? "the cache service was set up with an older Tuist" : nil
    }
}

enum XcodeCacheInstallationStoreError: Error {
    case invalidLaunchAgent
}
