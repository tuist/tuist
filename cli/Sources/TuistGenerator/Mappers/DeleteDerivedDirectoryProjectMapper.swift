import FileSystem
import Foundation
import TuistCore
import TuistSupport
import XcodeGraph

/// A project mapper that returns side effects to delete the derived directory.
public final class DeleteDerivedDirectoryProjectMapper: ProjectMapping {
    private let derivedDirectoryName: String
    private let fileHandler: FileHandling
    private let fileSystem: FileSysteming

    public init(
        derivedDirectoryName: String = Constants.DerivedDirectory.name,
        fileHandler: FileHandling = FileHandler.shared,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.derivedDirectoryName = derivedDirectoryName
        self.fileHandler = fileHandler
        self.fileSystem = fileSystem
    }

    // MARK: - ProjectMapping

    public func map(project: Project) async throws -> (Project, [SideEffectDescriptor]) {
        Logger.current.debug("Transforming project \(project.name): Deleting /Derived directory")

        let derivedDirectoryPath = project.path.appending(component: derivedDirectoryName)

        if try await !fileSystem.exists(derivedDirectoryPath) {
            return (project, [])
        }

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
