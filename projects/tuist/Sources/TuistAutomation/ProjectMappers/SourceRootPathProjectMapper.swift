import Foundation
import TSCBasic
import TuistCore
import TuistGraph

/// Automation commands create their own project in temporary directory
/// This means `SRCROOT` has a different path from the directory where `.xcodeproj` resides
/// `SRCROOT` should point to the directory of the target sources
/// To ensure projects still build, we need to overwrite `SRCROOT` variable ourselves
/// This should be used only for automation projects as they are not expected to have their location changed after generation
public final class SourceRootPathProjectMapper: ProjectMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var project = project
        var base = project.settings.base
        // Keep the value if defined by user
        if base["SRCROOT"] == nil {
            base["SRCROOT"] = SettingValue(stringLiteral: project.sourceRootPath.pathString)
        }
        project.settings = project.settings.with(
            base: base
        )
        return (project, [])
    }
}
