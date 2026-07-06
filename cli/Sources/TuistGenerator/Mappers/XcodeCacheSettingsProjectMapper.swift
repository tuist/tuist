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
    private let casPluginPath: AbsolutePath?

    public init(tuist: Tuist, casPluginPath: AbsolutePath? = nil) {
        self.tuist = tuist
        self.casPluginPath = casPluginPath
    }

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
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
        if let fullHandle = tuist.fullHandle, let casPluginPath {
            // Route Xcode's compilation caching through the Tuist CAS plugin,
            // which owns remote (kura) read/write-through via the per-machine
            // proxy. Deliberately no COMPILATION_CACHE_REMOTE_SERVICE_PATH:
            // that is the daemon-socket path the plugin replaces.
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

        project.settings = Settings(
            base: baseSettings,
            configurations: project.settings.configurations,
            defaultSettings: project.settings.defaultSettings
        )

        return (project, [])
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
