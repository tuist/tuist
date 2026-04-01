import Foundation
import Logging
import TuistConfig
import TuistCore
import XcodeGraph

/// Sets the project-level `SWIFT_VERSION` build setting when a `defaultSwiftVersion` is specified
/// in the Tuist generation options. This allows `DefaultSettingsProvider` to skip injecting its
/// built-in default, so all local targets inherit the user-chosen version instead.
public struct DefaultSwiftVersionProjectMapper: ProjectMapping {
    private let tuist: Tuist

    public init(tuist: Tuist) {
        self.tuist = tuist
    }

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        guard let defaultSwiftVersion = tuist.project.generatedProject?.generationOptions.defaultSwiftVersion else {
            return (project, [])
        }

        Logger.current
            .debug(
                "Transforming project \(project.name): Setting default SWIFT_VERSION to \(defaultSwiftVersion)"
            )

        var project = project
        var baseSettings = project.settings.base
        baseSettings["SWIFT_VERSION"] = .string(defaultSwiftVersion)

        project.settings = Settings(
            base: baseSettings,
            configurations: project.settings.configurations,
            defaultSettings: project.settings.defaultSettings
        )

        return (project, [])
    }
}
