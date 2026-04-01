import Foundation
import TuistConfig
import TuistCore
import XcodeGraph

/// Sets `SWIFT_VERSION` in the project's base settings from the `defaultSwiftVersion` generation option.
///
/// `DefaultSettingsProvider` skips injecting its built-in `"5.0"` default when it finds `SWIFT_VERSION`
/// already present in `project.settings.base`, so this mapper is the single source of truth for the
/// default Swift version applied to local targets.
public struct DefaultSwiftVersionProjectMapper: ProjectMapping {
    private let defaultSwiftVersion: String

    public init(defaultSwiftVersion: String) {
        self.defaultSwiftVersion = defaultSwiftVersion
    }

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
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
