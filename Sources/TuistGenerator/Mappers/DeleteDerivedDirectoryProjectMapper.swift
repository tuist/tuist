import Foundation
import TuistCore
import TuistSupport

/// A mapper that returns side effects to delete the derived directory of each project of the graph.
public class DeleteDerivedDirectoryProjectMapper: ProjectMapping {
    public init() {}

    // MARK: - GraphMapping

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        logger.debug("Determining the /Derived directories that should be delted")
        let derivedDirectoryPath = project.path.appending(component: Constants.DerivedFolder.name)
        let directoryDescriptor = DirectoryDescriptor(path: derivedDirectoryPath, state: .absent)

        return (project, [
            .directory(directoryDescriptor),
        ])
    }
}
