import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.FileElement {
    /// Maps a ProjectDescription.FileElement instance into a [XcodeGraph.FileElement] instance.
    /// Glob patterns in file elements are unfolded as part of the mapping.
    /// - Parameters:
    ///   - manifest: Manifest representation of the file element.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.FileElement,
        generatorPaths: GeneratorPaths,
        includeFiles: @escaping (AbsolutePath) -> Bool = { _ in true }
    ) async throws -> [XcodeGraph.FileElement] {
        let fileSystem = FileSystem()
        func globFiles(_ path: AbsolutePath) async throws -> [AbsolutePath] {
            if try await fileSystem.exists(path), !FileHandler.shared.isFolder(path) { return [path] }

            let files = try FileHandler.shared.throwingGlob(AbsolutePath.root, glob: String(path.pathString.dropFirst()))
                .filter(includeFiles)

            if files.isEmpty {
                if FileHandler.shared.isFolder(path) {
                    logger.warning("'\(path.pathString)' is a directory, try using: '\(path.pathString)/**' to list its files")
                } else {
                    // FIXME: This should be done in a linter.
                    logger.warning("No files found at: \(path.pathString)")
                }
            }

            return files
        }

        func folderReferences(_ path: AbsolutePath) async throws -> [AbsolutePath] {
            guard try await fileSystem.exists(path) else {
                // FIXME: This should be done in a linter.
                logger.warning("\(path.pathString) does not exist")
                return []
            }

            guard FileHandler.shared.isFolder(path) else {
                // FIXME: This should be done in a linter.
                logger.warning("\(path.pathString) is not a directory - folder reference paths need to point to directories")
                return []
            }

            return [path]
        }

        switch manifest {
        case let .glob(pattern: pattern):
            let resolvedPath = try generatorPaths.resolve(path: pattern)
            return try await globFiles(resolvedPath).map(FileElement.file)
        case let .folderReference(path: folderReferencePath):
            let resolvedPath = try generatorPaths.resolve(path: folderReferencePath)
            return try await folderReferences(resolvedPath).map(FileElement.folderReference)
        }
    }
}
