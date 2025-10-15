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
        guard tuist.project.generatedProject?.generationOptions.enableCaching == true else {
            return (project, [])
        }

        Logger.current
            .debug(
                "Transforming project \(project.name): Adding Xcode cache compilation settings"
            )

        var project = project

        // Get existing base settings
        var baseSettings = project.settings.base

        // Add the cache settings
        baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] = .string("YES")

        // Get the socket path for this project's fullHandle
        if let fullHandle = tuist.fullHandle {
            let socketPath = Environment.current.socketPath(for: fullHandle)

            // Replace home directory with $HOME for portability
            let homeDir = Environment.current.homeDirectory.pathString
            let socketPathString = socketPath.pathString
            let portableSocketPath: String
            if socketPathString.hasPrefix(homeDir) {
                portableSocketPath = "$HOME" + socketPathString.dropFirst(homeDir.count)
            } else {
                portableSocketPath = socketPathString
            }

            baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] = .string(portableSocketPath)
        }

        baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] = .string("YES")

        // Update project settings with new base settings
        project.settings = Settings(
            base: baseSettings,
            configurations: project.settings.configurations,
            defaultSettings: project.settings.defaultSettings
        )

        return (project, [])
    }
}
