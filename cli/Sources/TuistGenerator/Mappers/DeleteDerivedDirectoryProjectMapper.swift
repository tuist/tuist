import FileSystem
import Foundation
import TuistConstants
import TuistCore
import TuistLogging
import XcodeGraph

/// A project mapper that returns side effects to delete the derived directory.
public struct DeleteDerivedDirectoryProjectMapper: ProjectMapping {
    private let derivedDirectoryName: String
    private let fileSystem: FileSysteming

    public init(
        derivedDirectoryName: String = Constants.DerivedDirectory.name,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.derivedDirectoryName = derivedDirectoryName
        self.fileSystem = fileSystem
    }

    // MARK: - ProjectMapping

    public func map(project: Project) async throws -> (Project, [SideEffectDescriptor]) {
        Logger.current.debug("Transforming project \(project.name): Deleting /Derived directory")

        let derivedDirectoryPath = project.path.appending(component: derivedDirectoryName)

        if try await !fileSystem.exists(derivedDirectoryPath) {
            return (project, [])
        }

        let contents = try await fileSystem.glob(directory: derivedDirectoryPath, include: ["*"]).collect()
        var sideEffects: [SideEffectDescriptor] = []
        // FrameworkSearchPaths holds the .resp files written by LinkGenerator as project side
        // effects, which run before these cleanup side effects. Deleting the directory here would
        // wipe the just-written response files (leaving the build referencing a missing @file),
        // so it is preserved; LinkGenerator overwrites its contents on every generation.
        for item in contents
            where item.extension != "modulemap" && item.basename != Constants.DerivedDirectory.frameworkSearchPaths
        {
            if try await fileSystem.exists(item, isDirectory: true) {
                sideEffects.append(.directory(DirectoryDescriptor(path: item, state: .absent)))
            } else {
                sideEffects.append(.file(FileDescriptor(path: item, state: .absent)))
            }
        }

        return (project, sideEffects)
    }
}
