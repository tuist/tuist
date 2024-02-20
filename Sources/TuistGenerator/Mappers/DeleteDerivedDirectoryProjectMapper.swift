import Foundation
import TuistCore
import TuistGraph
import TuistSupport

/// A project mapper that returns side effects to delete the derived directory.
public final class DeleteDerivedDirectoryProjectMapper: ProjectMapping {
    private let derivedDirectoryName: String
    private let fileHandler: FileHandling
    
    public init(
        derivedDirectoryName: String = Constants.DerivedDirectory.name,
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.derivedDirectoryName = derivedDirectoryName
        self.fileHandler = fileHandler
    }

    // MARK: - ProjectMapping

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        logger.debug("Transforming project \(project.name): Deleting /Derived directory")

        let derivedDirectoryPath = project.path.appending(component: derivedDirectoryName)
        
        let sideEffects: [SideEffectDescriptor] = try fileHandler.contentsOfDirectory(derivedDirectoryPath)
            .filter { $0.extension != "modulemap" }
            .map {
                if fileHandler.isFolder($0) {
                    return .directory(DirectoryDescriptor(path: $0, state: .absent))
                } else {
                    return .file(FileDescriptor(path: $0, state: .absent))
                }
            }

        return (project, sideEffects)
    }
}
