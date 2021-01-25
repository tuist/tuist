import Foundation
import TuistCore
import TuistGraph
import TuistSupport

/// A project mapper that returns side effects to delete the derived directory.
public final class DeleteDerivedDirectoryProjectMapper: ProjectMapping {
    private let derivedDirectoryName: String

    public init(derivedDirectoryName: String = Constants.DerivedDirectory.name) {
        self.derivedDirectoryName = derivedDirectoryName
    }

    // MARK: - ProjectMapping

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        logger.debug("Determining the /Derived directories that should be deleted within \(project.path)")
        let derivedDirectoryPath = project.path.appending(component: derivedDirectoryName)
        let directoryDescriptor = DirectoryDescriptor(path: derivedDirectoryPath, state: .absent)

        return (project, [
            .directory(directoryDescriptor),
        ])
    }
}
