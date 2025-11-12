import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.CopyFileElement {
    /// Maps a ProjectDescription.FileElement instance into a [XcodeGraph.FileElement] instance.
    /// Glob patterns in file elements are unfolded as part of the mapping.
    /// - Parameters:
    ///   - manifest: Manifest representation of the file element.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.CopyFileElement,
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming,
        includeFiles: @escaping (AbsolutePath) -> Bool = { _ in true }
    ) async throws -> [XcodeGraph.CopyFileElement] {
        func globFiles(_ path: AbsolutePath) async throws -> [AbsolutePath] {
            if try await fileSystem.exists(path), !FileHandler.shared.isFolder(path) { return [path] }

            let files: [AbsolutePath]

            do {
                files = try await fileSystem.throwingGlob(
                    directory: AbsolutePath.root,
                    include: [String(path.pathString.dropFirst())]
                )
                .collect()
                .filter(includeFiles)
                .sorted()
            } catch GlobError.nonExistentDirectory {
                files = []
            }

            // File validation is now handled by ManifestMapperLinter
            // Empty files array is valid and will be checked during linting phase

            return files
        }

        func folderReferences(_ path: AbsolutePath) async throws -> [AbsolutePath] {
            // Validation is now handled by ManifestMapperLinter
            // Return empty array if path doesn't exist or is not a folder
            guard try await fileSystem.exists(path) else {
                return []
            }

            guard FileHandler.shared.isFolder(path) else {
                return []
            }

            return [path]
        }

        switch manifest {
        case let .glob(pattern: pattern, condition: condition, codeSignOnCopy: codeSign):
            let resolvedPath = try generatorPaths.resolve(path: pattern)
            return try await globFiles(resolvedPath).map { .file(
                path: $0,
                condition: condition?.asGraphCondition,
                codeSignOnCopy: codeSign
            )
            }
        case let .folderReference(path: folderReferencePath, condition: condition, codeSignOnCopy: codeSign):
            let resolvedPath = try generatorPaths.resolve(path: folderReferencePath)
            return try await folderReferences(resolvedPath).map { .folderReference(
                path: $0,
                condition: condition?.asGraphCondition,
                codeSignOnCopy: codeSign
            ) }
        }
    }
}
