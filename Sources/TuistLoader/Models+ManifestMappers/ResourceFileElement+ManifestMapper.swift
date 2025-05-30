import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.ResourceFileElement {
    /// Maps a ProjectDescription.ResourceFileElement instance into a [XcodeGraph.ResourceFileElement] instance.
    /// Glob patterns in file elements are unfolded as part of the mapping.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the file element.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.ResourceFileElement,
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming,
        includeFiles: @escaping (AbsolutePath) -> Bool = { _ in true }
    ) async throws -> [XcodeGraph.ResourceFileElement] {
        func globFiles(_ path: AbsolutePath, excluding: [String]) async throws -> [AbsolutePath] {
            var excluded: Set<AbsolutePath> = []
            for path in excluding {
                let absolute = try AbsolutePath(validating: path)
                let globs = try await fileSystem.glob(
                    directory: .root,
                    include: [String(absolute.pathString.dropFirst())]
                )
                .collect()
                excluded.formUnion(globs)
            }

            let files = try await fileSystem
                .throwingGlob(directory: .root, include: [String(path.pathString.dropFirst())])
                .collect()
                .filter(includeFiles)
                .filter { !excluded.contains($0) }

            if files.isEmpty {
                if FileHandler.shared.isFolder(path) {
                    Logger.current
                        .warning("'\(path.pathString)' is a directory, try using: '\(path.pathString)/**' to list its files")
                } else if !path.isGlobPath {
                    // FIXME: This should be done in a linter.
                    Logger.current.warning("No files found at: \(path.pathString)")
                }
            }

            return files
                .compactMap { $0.opaqueParentDirectory() ?? $0 }
                .uniqued()
        }

        func folderReferences(_ path: AbsolutePath) async throws -> [AbsolutePath] {
            guard try await fileSystem.exists(path) else {
                // FIXME: This should be done in a linter.
                Logger.current.warning("\(path.pathString) does not exist")
                return []
            }

            guard FileHandler.shared.isFolder(path) else {
                // FIXME: This should be done in a linter.
                Logger.current
                    .warning("\(path.pathString) is not a directory - folder reference paths need to point to directories")
                return []
            }

            return [path]
        }

        switch manifest {
        case let .glob(pattern, excluding, tags, condition):
            let resolvedPath = try generatorPaths.resolve(path: pattern)
            let excluding: [String] = try excluding.compactMap { try generatorPaths.resolve(path: $0).pathString }
            return try await globFiles(resolvedPath, excluding: excluding).map { ResourceFileElement.file(
                path: $0,
                tags: tags,
                inclusionCondition: condition?.asGraphCondition
            ) }
            .sorted(by: { $0.path < $1.path })
        case let .folderReference(folderReferencePath, tags, condition):
            let resolvedPath = try generatorPaths.resolve(path: folderReferencePath)
            return try await folderReferences(resolvedPath).map { ResourceFileElement.folderReference(
                path: $0,
                tags: tags,
                inclusionCondition: condition?.asGraphCondition
            ) }
            .sorted(by: { $0.path < $1.path })
        }
    }
}
