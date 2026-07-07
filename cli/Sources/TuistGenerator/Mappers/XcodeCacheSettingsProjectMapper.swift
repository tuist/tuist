import FileSystem
import Foundation
import Logging
import Path
import TuistConfig
import TuistCore
import TuistEnvironment
import TuistSupport
import XcodeGraph

/// This mapper adds Xcode cache compilation settings when enableCaching is enabled in the Tuist configuration.
/// When enableCaching is true, local CAS (Compilation Caching Service) settings are added.
/// When a fullHandle is also provided, remote caching settings are additionally configured.
public struct XcodeCacheSettingsProjectMapper: ProjectMapping {
    private let tuist: Tuist
    private let kuraEnabled: Bool
    private let casPluginCandidates: [AbsolutePath]
    private let fileSystem: FileSysteming

    public init(
        tuist: Tuist,
        kuraEnabled: Bool = false,
        casPluginCandidates: [AbsolutePath] = [],
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.tuist = tuist
        self.kuraEnabled = kuraEnabled
        self.casPluginCandidates = casPluginCandidates
        self.fileSystem = fileSystem
    }

    public func map(project: Project) async throws -> (Project, [SideEffectDescriptor]) {
        guard tuist.project.generatedProject?.generationOptions.enableCaching ?? false else {
            return (project, [])
        }

        Logger.current
            .debug(
                "Transforming project \(project.name): Adding Xcode cache compilation settings"
            )

        var project = project
        var baseSettings = project.settings.base

        baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] = "YES"
        if let fullHandle = tuist.fullHandle {
            if kuraEnabled {
                // kura path: route Xcode's compilation caching through the Tuist
                // CAS plugin, which owns remote (kura) read/write-through via the
                // per-machine proxy. Needs the bundled dylib; when it is absent the
                // build stays on local-only caching rather than a broken plugin path.
                if let casPluginPath = try await resolvedCASPluginPath() {
                    baseSettings["COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS"] = "YES"
                    baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] = "YES"
                    baseSettings["COMPILATION_CACHE_PLUGIN_PATH"] = .string(casPluginPath.pathString)
                    // Hand the plugin the account/project as a compiler option, which
                    // reaches every frontend — including an Xcode ⌘B build that carries
                    // no CLI environment — so the proxy can route without the CLI. Swift
                    // only; C/ObjC frontends fall back to the proxy's routing registry.
                    baseSettings["OTHER_SWIFT_FLAGS"] = Self.appendingCASInstanceFlag(
                        fullHandle: fullHandle,
                        to: baseSettings["OTHER_SWIFT_FLAGS"]
                    )
                }
            } else {
                // Legacy path (accounts not yet on kura): Xcode's built-in remote-cache
                // service, backed by the per-project `tuist cache start` daemon that
                // `tuist setup cache` installs. `COMPILATION_CACHE_REMOTE_SERVICE_PATH`
                // is the daemon's unix-socket path.
                baseSettings["COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS"] = "YES"
                baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] = "YES"
                baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] = .string(
                    Environment.current.cacheSocketPathString(for: fullHandle)
                )
            }
        }

        project.settings = Settings(
            base: baseSettings,
            configurations: project.settings.configurations,
            defaultSettings: project.settings.defaultSettings
        )

        return (project, [])
    }

    /// The first CAS plugin dylib candidate that exists on disk, or `nil` when
    /// none are present (the build then gets local-only compilation caching
    /// rather than a `COMPILATION_CACHE_PLUGIN_PATH` pointing at a missing file).
    private func resolvedCASPluginPath() async throws -> AbsolutePath? {
        for candidate in casPluginCandidates where try await fileSystem.exists(candidate) {
            return candidate
        }
        return nil
    }

    /// Appends `-cas-plugin-option tuist-instance=<fullHandle>` to an existing
    /// `OTHER_SWIFT_FLAGS` value, preserving inherited flags.
    private static func appendingCASInstanceFlag(
        fullHandle: String,
        to existing: SettingValue?
    ) -> SettingValue {
        let flags = ["-cas-plugin-option", "tuist-instance=\(fullHandle)"]
        switch existing {
        case let .array(values):
            return .array(values + flags)
        case let .string(value):
            return .array([value] + flags)
        case nil:
            return .array(["$(inherited)"] + flags)
        }
    }
}
