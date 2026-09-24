import FileSystem
import Foundation
import Path
import TuistConstants
import TuistCore
import TuistLogging
import XcodeGraph

/// A project mapper that returns side effects to delete the derived directory.
///
/// Generated test plans are preserved because they are written while the `.xcodeproj` is
/// being written, before mapper side effects run; deleting the directory here would remove
/// the plans right after they were generated.
public struct DeleteDerivedDirectoryProjectMapper: ProjectMapping {
    private let derivedDirectoryName: String
    private let preservedDerivedDirectories: Set<String>
    private let fileSystem: FileSysteming

    public init(
        derivedDirectoryName: String = Constants.DerivedDirectory.name,
        preservedDerivedDirectories: Set<String> = [
            Constants.DerivedDirectory.moduleMaps,
            Constants.DerivedDirectory.frameworkSearchPaths,
            Constants.DerivedDirectory.sources,
            Constants.DerivedDirectory.infoPlists,
            Constants.DerivedDirectory.entitlements,
            Constants.DerivedDirectory.testPlans,
        ],
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.derivedDirectoryName = derivedDirectoryName
        self.preservedDerivedDirectories = preservedDerivedDirectories
        self.fileSystem = fileSystem
    }

    // MARK: - ProjectMapping

    public func map(project: Project) async throws -> (Project, [SideEffectDescriptor]) {
        Logger.current.debug("Transforming project \(project.name): Deleting /Derived directory")

        let derivedDirectoryPath = project.path.appending(component: derivedDirectoryName)

        if try await !fileSystem.exists(derivedDirectoryPath) {
            return (project, [])
        }

        let contents = try await fileSystem.contentsOfDirectory(derivedDirectoryPath)
        var sideEffects: [SideEffectDescriptor] = []
        for item in contents where !item.basename.hasPrefix(".") {
            if let sideEffect = try await deletionSideEffect(for: item) {
                sideEffects.append(sideEffect)
            }
        }

        return (project, sideEffects)
    }

    private func deletionSideEffect(for item: AbsolutePath) async throws -> SideEffectDescriptor? {
        guard item.extension != "modulemap" else { return nil }
        if let sideEffect = try symbolicLinkDeletion(at: item) { return sideEffect }
        guard try await fileSystem.exists(item, isDirectory: true) else {
            return .file(FileDescriptor(path: item, state: .absent))
        }
        guard !preservedDerivedDirectories.contains(item.basename) else { return nil }
        return .directory(DirectoryDescriptor(path: item, state: .absent))
    }

    private func symbolicLinkDeletion(at path: AbsolutePath) throws -> SideEffectDescriptor? {
        // Unlike resolveSymbolicLink, this also recognizes links whose destinations no longer exist.
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path.pathString) else { return nil }
        return .symbolicLink(SymbolicLinkDescriptor(
            path: path,
            destination: try AbsolutePath(validating: destination, relativeTo: path.parentDirectory),
            state: .absent
        ))
    }
}
