import FileSystem
import Foundation
import Logging
import Path
import struct TSCUtility.Version
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
    private let casPluginCandidates: [AbsolutePath]
    private let fileSystem: FileSysteming

    public init(
        tuist: Tuist,
        casPluginCandidates: [AbsolutePath] = [],
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.tuist = tuist
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

        // Without prefix mapping a cache key embeds absolute paths — DerivedData's
        // above all — so the same compilation caches under a different key on every
        // machine, and artifacts can't be replayed between developers or between
        // local and CI. Xcode 27 (Swift 6.4) is the first build system to implement
        // the source/build directory mappings, and Apple ships them off (the
        // settings carry no default, for staged adoption), so opt in explicitly.
        // Enabling them changes every key, but only ever at a boundary where the
        // compiler version already invalidated the cache.
        if await Self.isPrefixMappingSupported() {
            baseSettings["SWIFT_ENABLE_PREFIX_MAPPING"] = "YES"
            baseSettings["SWIFT_ENABLE_PROJECT_PREFIX_MAPPING"] = "YES"
            baseSettings["CLANG_ENABLE_PREFIX_MAPPING"] = "YES"
            baseSettings["CLANG_ENABLE_PROJECT_PREFIX_MAPPING"] = "YES"
        }

        var casPluginOptions: [String] = []
        if let fullHandle = tuist.fullHandle {
            // Route Xcode's compilation caching through the Tuist CAS plugin,
            // which owns remote (Kura) read/write-through via the per-machine
            // proxy. Needs the bundled dylib; when it is absent the build stays
            // on local-only caching rather than a broken plugin path.
            if let casPluginPath = try await resolvedCASPluginPath() {
                baseSettings["COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS"] = "YES"
                baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] = "YES"
                baseSettings["COMPILATION_CACHE_PLUGIN_PATH"] = Self.pluginPathSetting(casPluginPath)
                // Hand the plugin its per-project options as compiler flags, which
                // reach every frontend — including an Xcode ⌘B build that carries
                // no CLI environment — so the proxy can route (and honor the upload
                // policy) without the CLI. These reach Swift only; the setting below
                // is what brings clang in.
                casPluginOptions = Self.casPluginOptionFlags(
                    fullHandle: fullHandle,
                    upload: tuist.xcodeCache.upload
                )
                baseSettings["OTHER_SWIFT_FLAGS"] = Self.appending(
                    casPluginOptions,
                    to: baseSettings["OTHER_SWIFT_FLAGS"]
                )
                // This is what makes C/ObjC, precompiled modules and PCHs shareable.
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
                // The path points at the machine-wide proxy, and the plugin CONSUMES
                // this option rather than forwarding it to the wrapped Apple plugin,
                // whose own remote client would otherwise run its much slower
                // choreography against this socket. So the flag flips without handing
                // Apple's client the connection.
                baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] = .string(
                    Environment.current.casProxySocketPathString()
                )
            } else {
                // The bundled dylib is absent, so the build silently falls back to
                // local-only caching (no remote). Warn rather than let a cold cache
                // be the first symptom.
                Logger.current.warning(
                    "Xcode Cache is enabled for \(fullHandle) but the CAS plugin (libtuist_cas_plugin.dylib) was not found next to `tuist`. This build will use local-only compilation caching with no remote cache. Reinstall Tuist, or set TUIST_CAS_PLUGIN_PATH to the dylib."
                )
            }
        }

        project.settings = Settings(
            base: baseSettings,
            configurations: project.settings.configurations,
            defaultSettings: project.settings.defaultSettings
        )

        // Xcode resolves `OTHER_SWIFT_FLAGS` at target and configuration levels
        // independently of the project base: any target- or configuration-level value
        // that lacks `$(inherited)` shadows the project base entirely, dropping the
        // `-cas-plugin-option tuist-instance=…` we just wrote. Without that option
        // reaching the frontend the CAS plugin has no instance to route to, and
        // swift-frontend rejects the combination of `-cache-compile-job`, `-cas-path`
        // and `-cas-plugin-path` with `cannot setup CAS due to conflicting '-cas-*'
        // options`. Mirror the pattern in `ModuleMapMapper` and patch each shadowing
        // level with the same flags.
        if !casPluginOptions.isEmpty {
            project.targets = project.targets.mapValues { target in
                Self.applyingCASPluginOptions(casPluginOptions, to: target)
            }
        }

        return (project, [])
    }

    /// Whether the selected Xcode's build system implements the source/build
    /// directory prefix mappings that make compilation-cache keys path-independent
    /// (Xcode 27 / Swift 6.4 and later).
    ///
    /// A version that can't be determined degrades to `false` — the status quo,
    /// path-dependent keys — rather than failing generation over a cache
    /// optimization.
    static func isPrefixMappingSupported() async -> Bool {
        guard let version = try? await XcodeController.current.selectedVersion() else { return false }
        return version >= Version(27, 0, 0)
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

    /// The CAS plugin dylib's path as it is written into the build setting.
    ///
    /// `$HOME`-relative for the same reason as the proxy socket: the value is baked
    /// into the generated pbxproj and reaches the target content hash through the
    /// project's base settings, so a raw install path (Homebrew locally, mise on CI)
    /// would give identical code a different module-cache key on every machine.
    /// A plugin installed outside `$HOME` has no prefix to factor out and is written
    /// verbatim.
    private static func pluginPathSetting(_ path: AbsolutePath) -> SettingValue {
        .string(Environment.current.homeRelativePathString(path))
    }

    /// The plugin's per-project `-cas-plugin-option` flags (`tuist-instance`, and
    /// `tuist-upload=false` when uploads are disabled).
    private static func casPluginOptionFlags(fullHandle: String, upload: Bool) -> [String] {
        var flags = ["-cas-plugin-option", "tuist-instance=\(fullHandle)"]
        if !upload {
            // `xcodeCache(upload:)` is per-project, but the proxy is machine-wide;
            // carry the opt-out as a plugin option so it reaches every frontend.
            flags += ["-cas-plugin-option", "tuist-upload=false"]
        }
        return flags
    }

    /// Appends `flags` to an existing `OTHER_SWIFT_FLAGS` value, preserving inherited
    /// flags when the setting is absent.
    private static func appending(
        _ flags: [String],
        to existing: SettingValue?
    ) -> SettingValue {
        switch existing {
        case let .array(values):
            return .array(values + flags)
        case let .string(value):
            return .array([value] + flags)
        case nil:
            return .array(["$(inherited)"] + flags)
        }
    }

    /// Patches any shadowing `OTHER_SWIFT_FLAGS` on the target with the CAS plugin
    /// options. Only levels that actually shadow the project base need the fix:
    /// - the target's `settings.base` when it defines `OTHER_SWIFT_FLAGS` without
    ///   `$(inherited)`
    /// - each configuration whose own `OTHER_SWIFT_FLAGS` lacks `$(inherited)`
    ///
    /// A value that already contains `$(inherited)` pulls the project base in and
    /// would land the plugin options twice if we appended again.
    private static func applyingCASPluginOptions(
        _ flags: [String],
        to target: Target
    ) -> Target {
        guard let settings = target.settings else { return target }
        var base = settings.base
        if let existing = base["OTHER_SWIFT_FLAGS"], !Self.inheritsBaseSetting(existing) {
            base["OTHER_SWIFT_FLAGS"] = Self.appending(flags, to: existing)
        }
        let configurations = settings.configurations.mapValues { configuration -> Configuration? in
            guard var configuration else { return nil }
            guard let existing = configuration.settings["OTHER_SWIFT_FLAGS"],
                  !Self.inheritsBaseSetting(existing)
            else { return configuration }
            var configurationSettings = configuration.settings
            configurationSettings["OTHER_SWIFT_FLAGS"] = Self.appending(flags, to: existing)
            configuration.settings = configurationSettings
            return configuration
        }
        var target = target
        target.settings = Settings(
            base: base,
            baseDebug: settings.baseDebug,
            configurations: configurations,
            defaultSettings: settings.defaultSettings,
            defaultConfiguration: settings.defaultConfiguration
        )
        return target
    }

    private static func inheritsBaseSetting(_ value: SettingValue) -> Bool {
        switch value {
        case let .string(string):
            return string.contains("$(inherited)")
        case let .array(values):
            return values.contains("$(inherited)")
        }
    }
}
