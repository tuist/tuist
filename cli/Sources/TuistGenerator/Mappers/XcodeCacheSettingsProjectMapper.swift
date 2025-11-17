import Foundation
import Logging
import Path
import TuistCore
import TuistSupport
import XcodeGraph

/// This mapper adds Xcode cache compilation settings when enableCaching is enabled in the Tuist configuration
public final class XcodeCacheSettingsProjectMapper: ProjectMapping {
    private let tuist: Tuist

    public init(tuist: Tuist) {
        self.tuist = tuist
    }

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        guard tuist.project.generatedProject?.generationOptions.enableCaching == true,
              let fullHandle = tuist.fullHandle
        else {
            return (project, [])
        }

        Logger.current
            .debug(
                "Transforming project \(project.name): Adding Xcode cache compilation settings"
            )

        var project = project

        var baseSettings = project.settings.base
        baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] = .string("YES")

        baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] = .string(
            Environment.current.cacheSocketPathString(for: fullHandle)
        )

        baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] = .string("YES")
        baseSettings["COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS"] = .string("YES")

        project.settings = Settings(
            base: baseSettings,
            configurations: project.settings.configurations,
            defaultSettings: project.settings.defaultSettings
        )

        return (project, [])
    }
}
