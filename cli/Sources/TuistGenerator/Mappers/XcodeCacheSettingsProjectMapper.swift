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

        baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] = "YES"
        if let fullHandle = tuist.fullHandle {
            // Remote caching settings - only when fullHandle is configured
            baseSettings["COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS"] = "YES"
            baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] = "YES"
            baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] = .string(
                Environment.current.cacheSocketPathString(for: fullHandle)
            )
        }

        project.settings = Settings(
            base: baseSettings,
            configurations: project.settings.configurations,
            defaultSettings: project.settings.defaultSettings
        )

        return (project, [])
    }
}
