import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.ResourceFileElement {
    /// Maps a ProjectDescription.ResourceFileElement instance into a [TuistGraph.ResourceFileElement] instance.
    /// Glob patterns in file elements are unfolded as part of the mapping.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the file element.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.ResourceFileElement,
        generatorPaths: GeneratorPaths,
        includeFiles: @escaping (AbsolutePath) -> Bool = { _ in true }
    ) throws -> [TuistGraph.ResourceFileElement] {
        func globFiles(_ path: AbsolutePath, excluding: [String]) throws -> [AbsolutePath] {
            var excluded: Set<AbsolutePath> = []
            try excluding.forEach { path in
                let absolute = try AbsolutePath(validating: path)
                let globs = try AbsolutePath(validating: absolute.dirname).glob(absolute.basename)
                excluded.formUnion(globs)
            }

            let files = try FileHandler.shared
                .throwingGlob(.root, glob: String(path.pathString.dropFirst()))
                .filter { !$0.isInOpaqueDirectory }
                .filter(includeFiles)
                .filter { !excluded.contains($0) }

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

        func folderReferences(_ path: AbsolutePath) -> [AbsolutePath] {
            guard FileHandler.shared.exists(path) else {
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
        case let .glob(pattern, excluding, tags):
            let resolvedPath = try generatorPaths.resolve(path: pattern)
            let excluding: [String] = try excluding.compactMap { try generatorPaths.resolve(path: $0).pathString }
            return try globFiles(resolvedPath, excluding: excluding).map { ResourceFileElement.file(path: $0, tags: tags) }
        case let .folderReference(folderReferencePath, tags):
            let resolvedPath = try generatorPaths.resolve(path: folderReferencePath)
            return folderReferences(resolvedPath).map { ResourceFileElement.folderReference(path: $0, tags: tags) }
        }
    }
}
