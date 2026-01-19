import Foundation
import Logging
import Path
import TuistCore
import TuistSupport
import XcodeGraph

/// This mapper adds Xcode cache compilation settings when enableCaching is enabled in the Tuist configuration.
/// When enableCaching is true, local CAS (Compilation Caching Service) settings are added.
/// When a fullHandle is also provided, remote caching settings are additionally configured.
public final class XcodeCacheSettingsProjectMapper: ProjectMapping {
    private let tuist: Tuist

    public init(tuist: Tuist) {
        self.tuist = tuist
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

        // Local CAS settings - enable compilation caching for Swift and Clang
        baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] = "YES"
        baseSettings["SWIFT_ENABLE_COMPILE_CACHE"] = "YES"
        baseSettings["CLANG_ENABLE_COMPILE_CACHE"] = "YES"
        baseSettings["SWIFT_ENABLE_EXPLICIT_MODULES"] = "YES"
        baseSettings["SWIFT_USE_INTEGRATED_DRIVER"] = "YES"
        baseSettings["CLANG_ENABLE_MODULES"] = "YES"

        // Remote caching settings - only when fullHandle is configured
        if let fullHandle = tuist.fullHandle {
            baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] = "YES"
            baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] = .string(
                Environment.current.cacheSocketPathString(for: fullHandle)
            )
            baseSettings["COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS"] = "YES"
        }

        project.settings = Settings(
            base: baseSettings,
            configurations: project.settings.configurations,
            defaultSettings: project.settings.defaultSettings
        )

        return (project, [])
    }
}
