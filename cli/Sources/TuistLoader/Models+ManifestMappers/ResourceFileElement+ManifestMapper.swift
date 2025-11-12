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

            let files: [AbsolutePath]

            do {
                files = try await fileSystem
                    .throwingGlob(directory: .root, include: [String(path.pathString.dropFirst())])
                    .collect()
                    .filter(includeFiles)
                    .filter { !excluded.contains($0) }
            } catch GlobError.nonExistentDirectory {
                files = []
            }

            // File validation moved to ManifestMapperLinter
            return files
                .compactMap { $0.opaqueParentDirectory() ?? $0 }
                .uniqued()
        }

        func folderReferences(_ path: AbsolutePath) async throws -> [AbsolutePath] {
            // Validation moved to ManifestMapperLinter
            guard try await fileSystem.exists(path) else {
                return []
            }

            guard FileHandler.shared.isFolder(path) else {
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
