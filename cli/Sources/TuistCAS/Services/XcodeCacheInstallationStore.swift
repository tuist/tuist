import Foundation
import Mockable
import struct TSCUtility.Version
import TuistEnvironment

@Mockable
public protocol XcodeCacheInstallationChecking {
    func warning(developerDirectory: URL?, xcodeBuildVersion: String?, tuistVersion: String) -> String?
}

/// Describes the last successful setup, not the plugin images already loaded by Xcode.
public struct XcodeCacheInstallationStore: XcodeCacheInstallationChecking {
    struct Installation: Codable {
        let tuistVersion: String
        let launchAgentProgram: String
        let launchAgentModifiedAt: Date
        let launchAgentProgramModifiedAt: Date?
        let developerDirectory: String?
        let xcodeBuildVersion: String?
        let pluginInstalled: Bool
        let proxyPath: String?
        let installedAt: Date
    }

    private struct LaunchAgent: Decodable {
        let program: String
        let environmentVariables: [String: String]?

        enum CodingKeys: String, CodingKey {
            case program = "Program"
            case environmentVariables = "EnvironmentVariables"
        }

        var developerDirectory: String? {
            environmentVariables?["DEVELOPER_DIR"].map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        }

        var resolvedProgram: String {
            URL(fileURLWithPath: program).resolvingSymlinksInPath().path
        }
    }

    private let directory: URL
    private let launchAgent: URL
    private var manifest: URL { directory.appendingPathComponent("cas-install.json") }
    private var installedPlugin: URL { directory.appendingPathComponent("libtuist_cas_plugin.dylib") }

    public init(directory: URL? = nil, launchAgent: URL? = nil) {
        self.directory = directory ?? URL(fileURLWithPath: Environment.current.casPluginInstallPath().parentDirectory.pathString)
        self.launchAgent = launchAgent ?? URL(fileURLWithPath: Environment.current.homeDirectory.pathString)
            .appendingPathComponent("Library/LaunchAgents/tuist.cas-proxy.plist")
    }

    /// Invalidate before changing setup, so partial failures cannot leave a trusted old record.
    public func invalidate() throws {
        do {
            try FileManager.default.removeItem(at: manifest)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    public func record(plugin: URL?, proxy: URL?, xcodeBuildVersion: String?, tuistVersion: String) throws {
        let configuration = try Data(contentsOf: launchAgent)
        let agent = try PropertyListDecoder().decode(LaunchAgent.self, from: configuration)
        guard !agent.program.isEmpty, let modifiedAt = Self.modificationDate(at: launchAgent) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let installation = Installation(
            tuistVersion: tuistVersion,
            launchAgentProgram: agent.resolvedProgram,
            launchAgentModifiedAt: modifiedAt,
            launchAgentProgramModifiedAt: Self.modificationDate(at: URL(fileURLWithPath: agent.program)),
            developerDirectory: agent.developerDirectory,
            xcodeBuildVersion: xcodeBuildVersion,
            pluginInstalled: plugin != nil,
            proxyPath: proxy?.resolvingSymlinksInPath().path,
            installedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(installation)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: manifest, options: .atomic)
    }

    public func warning(developerDirectory: URL?, xcodeBuildVersion: String?, tuistVersion: String) -> String? {
        let fileManager = FileManager.default
        let hasAgent = fileManager.fileExists(atPath: launchAgent.path)
        // Teardown deliberately keeps the stable plugin for existing projects.
        // A plugin alone is not evidence of an active or broken proxy setup.
        guard hasAgent || fileManager.fileExists(atPath: manifest.path) else { return nil }

        let recorded = try? JSONDecoder().decode(Installation.self, from: Data(contentsOf: manifest))
        let configuration = try? Data(contentsOf: launchAgent)
        let agent = configuration.flatMap { try? PropertyListDecoder().decode(LaunchAgent.self, from: $0) }
        // Older CLIs do not invalidate this file. Trust it only while the actual
        // LaunchAgent (including symlink targets) still matches the setup record.
        let installation = recorded.flatMap { record in
            record.launchAgentModifiedAt == Self.modificationDate(at: launchAgent)
                && record.launchAgentProgram == agent?.resolvedProgram
                && record.launchAgentProgramModifiedAt == agent
                .flatMap { Self.modificationDate(at: URL(fileURLWithPath: $0.program)) }
                && record.developerDirectory == agent?.developerDirectory ? record : nil
        }
        var reasons: [String] = []
        if !hasAgent {
            reasons.append("the cache proxy's LaunchAgent is missing")
        } else if agent == nil || agent?.program.isEmpty == true {
            reasons.append("the cache proxy's LaunchAgent configuration could not be read")
        } else if installation == nil {
            reasons.append("the cache setup version could not be verified (legacy or changed setup)")
        }
        if let program = agent?.program, !fileManager.fileExists(atPath: program) {
            reasons.append("the Tuist installation used to launch the cache proxy has been removed")
        }
        if let configuredDirectory = agent?.developerDirectory, let developerDirectory,
           developerDirectory.resolvingSymlinksInPath().path != configuredDirectory
        {
            reasons.append("the proxy was configured with a different Xcode (\(configuredDirectory))")
        }
        if let installation {
            if let warning = versionWarning(installation.tuistVersion, currentVersion: tuistVersion) {
                reasons.append(warning)
            }
            if let xcodeBuildVersion, installation.xcodeBuildVersion != xcodeBuildVersion {
                reasons.append("the setup-time Xcode build differs or was not recorded")
            }
            if installation.pluginInstalled, !fileManager.fileExists(atPath: installedPlugin.path) {
                reasons.append("the installed cache plugin is missing")
            }
            if let proxyPath = installation.proxyPath, !fileManager.fileExists(atPath: proxyPath) {
                reasons.append("the configured cache proxy's installation has been removed")
            }
        }
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

    private static func modificationDate(at url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }
}
