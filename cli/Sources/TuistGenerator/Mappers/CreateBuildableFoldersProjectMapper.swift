import Path
import TuistCore
import TuistLogging
import XcodeGraph

/// Creates the buildable folders that declare their contents.
///
/// Such a folder is referenced even when nothing has written to it yet (git doesn't keep empty directories, and the
/// derived directory is cleaned on every generation), so the tool that fills it and Xcode's folder watcher find it.
/// It must run after `DeleteDerivedDirectoryProjectMapper`, whose side effects may remove the folder.
public struct CreateBuildableFoldersProjectMapper: ProjectMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        let paths = Set(
            project.targets.values.flatMap { target in
                target.buildableFolders.filter { $0.contents != nil }.map(\.path)
            }
        )
        guard !paths.isEmpty else { return (project, []) }
        Logger.current.debug("Transforming project \(project.name): Creating buildable folders with declared contents")
        return (project, paths.sorted().map { .directory(DirectoryDescriptor(path: $0, state: .present)) })
    }
}
