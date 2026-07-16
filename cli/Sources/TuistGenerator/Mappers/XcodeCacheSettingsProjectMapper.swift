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
                    // Hand the plugin its per-project options as compiler flags, which
                    // reach every frontend — including an Xcode ⌘B build that carries
                    // no CLI environment — so the proxy can route (and honor the upload
                    // policy) without the CLI. These reach Swift only; the setting below
                    // is what brings clang in.
                    baseSettings["OTHER_SWIFT_FLAGS"] = Self.appendingCASPluginOptions(
                        fullHandle: fullHandle,
                        upload: tuist.xcodeCache.upload,
                        to: baseSettings["OTHER_SWIFT_FLAGS"]
                    )
                    // This is what makes C/ObjC, precompiled modules and PCHs shareable,
                    // and it is easy to mistake for the legacy daemon's socket setting.
                    //
                    // clang does not load a CAS plugin, so left alone it caches only into
                    // Xcode's builtin CAS, which never leaves the machine. The build system
                    // covers clang itself instead, but only where it considers a remote
                    // cache present, and it decides that purely by `remoteServicePath != nil`
                    // (swift-build's `CASOptions.hasRemoteCache`). That one flag gates both
                    // halves: uploading a clang or module output after a successful compile,
                    // and requesting the materialize-key task that fetches one back. Leave
                    // this unset and neither happens, so every C/ObjC/PCM/PCH compile stays
                    // local and a machine with a cold cache recompiles all of it. Measured on
                    // mastodon against an empty CAS: 259/930 tasks cached without this,
                    // 930/930 with it.
                    //
                    // The path points at the machine-wide proxy, not a per-project daemon,
                    // and the plugin CONSUMES this option rather than forwarding it to the
                    // wrapped Apple plugin, whose own remote client would otherwise run its
                    // much slower choreography against this socket. So the flag flips
                    // without handing Apple's client the connection.
                    baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] = .string(
                        Environment.current.casProxySocketPathString()
                    )
                } else {
                    // Kura is enabled but the bundled dylib is absent, so the build
                    // silently falls back to local-only caching (no remote). Warn
                    // rather than let a cold cache be the first symptom.
                    Logger.current.warning(
                        "Xcode Cache is enabled for \(fullHandle) but the CAS plugin (libtuist_cas_plugin.dylib) was not found next to `tuist`. This build will use local-only compilation caching with no remote cache. Reinstall Tuist, or set TUIST_CAS_PLUGIN_PATH to the dylib."
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

    /// Appends the plugin's per-project `-cas-plugin-option` flags
    /// (`tuist-instance`, and `tuist-upload=false` when uploads are disabled) to
    /// an existing `OTHER_SWIFT_FLAGS` value, preserving inherited flags.
    private static func appendingCASPluginOptions(
        fullHandle: String,
        upload: Bool,
        to existing: SettingValue?
    ) -> SettingValue {
        var flags = ["-cas-plugin-option", "tuist-instance=\(fullHandle)"]
        if !upload {
            // `xcodeCache(upload:)` is per-project, but the proxy is machine-wide;
            // carry the opt-out as a plugin option so it reaches every frontend.
            flags += ["-cas-plugin-option", "tuist-upload=false"]
        }
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
