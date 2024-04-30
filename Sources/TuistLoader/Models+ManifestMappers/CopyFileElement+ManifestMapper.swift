import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.CopyFileElement {
    /// Maps a ProjectDescription.FileElement instance into a [TuistGraph.FileElement] instance.
    /// Glob patterns in file elements are unfolded as part of the mapping.
    /// - Parameters:
    ///   - manifest: Manifest representation of the file element.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.CopyFileElement,
        generatorPaths: GeneratorPaths,
        includeFiles: @escaping (AbsolutePath) -> Bool = { _ in true }
    ) throws -> [TuistGraph.CopyFileElement] {
        func globFiles(_ path: AbsolutePath) throws -> [AbsolutePath] {
            if FileHandler.shared.exists(path), !FileHandler.shared.isFolder(path) { return [path] }

            if !path.pathString.isGlobComponent {
                return [path]
            }

            let files = try FileHandler.shared.throwingGlob(AbsolutePath.root, glob: String(path.pathString.dropFirst()))
                .filter(includeFiles)

            if files.isEmpty && FileHandler.shared.isFolder(path) {
                logger.warning("'\(path.pathString)' is a directory, try using: '\(path.pathString)/**' to list its files")
            }

            return files
        }

        switch manifest {
        case let .glob(pattern: pattern, condition: condition):
            let resolvedPath = try generatorPaths.resolve(path: pattern)
            return try globFiles(resolvedPath).map { .file(path: $0, condition: condition?.asGraphCondition) }
        case let .folderReference(path: folderReferencePath, condition: condition):
            let resolvedPath = try generatorPaths.resolve(path: folderReferencePath)
            return [resolvedPath].map { .folderReference(path: $0, condition: condition?.asGraphCondition) }
        }
    }
}
