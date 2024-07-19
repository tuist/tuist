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
        includeFiles: @escaping (AbsolutePath) -> Bool = { _ in true }
    ) throws -> [XcodeGraph.ResourceFileElement] {
        func globFiles(_ path: AbsolutePath, excluding: [String]) throws -> [AbsolutePath] {
            var excluded: Set<AbsolutePath> = []
            for path in excluding {
                let absolute = try AbsolutePath(validating: path)
                let globs = try AbsolutePath(validating: absolute.dirname).glob(absolute.basename)
                excluded.formUnion(globs)
            }

            if !path.pathString.isGlobComponent {
                return [path]
            }

            let files = try FileHandler.shared
                .throwingGlob(.root, glob: String(path.pathString.dropFirst()))
                .filter { !$0.isInOpaqueDirectory }
                .filter(includeFiles)
                .filter { !excluded.contains($0) }

            if files.isEmpty {
                logger.warning("'\(path.pathString)' is a directory, try using: '\(path.pathString)/**' to list its files")
            }

            return files
        }

        switch manifest {
        case let .glob(pattern, excluding, tags, condition):
            let resolvedPath = try generatorPaths.resolve(path: pattern)
            let excluding: [String] = try excluding.compactMap { try generatorPaths.resolve(path: $0).pathString }
            return try globFiles(resolvedPath, excluding: excluding).map { ResourceFileElement.file(
                path: $0,
                tags: tags,
                inclusionCondition: condition?.asGraphCondition
            ) }
        case let .folderReference(folderReferencePath, tags, condition):
            let resolvedPath = try generatorPaths.resolve(path: folderReferencePath)
            return [resolvedPath].map { ResourceFileElement.folderReference(
                path: $0,
                tags: tags,
                inclusionCondition: condition?.asGraphCondition
            ) }
        }
    }
}
