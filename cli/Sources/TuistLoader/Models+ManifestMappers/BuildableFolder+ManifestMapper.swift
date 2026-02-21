import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.BuildableFolder {
    static func from(
        manifest: ProjectDescription.BuildableFolder,
        generatorPaths: GeneratorPaths
    ) async throws -> XcodeGraph.BuildableFolder {
        let path = try generatorPaths.resolve(path: manifest.path)
        let fileSystem = FileSystem()

        let exclusionPatterns = manifest.exceptions.exceptions.flatMap(\.excluded)

        var exclusions = Set<AbsolutePath>()
        for pattern in exclusionPatterns {
            let expandedPaths = try await fileSystem.glob(directory: path, include: [pattern]).collect()
            exclusions.formUnion(expandedPaths)
        }

        let exceptions = try await XcodeGraph.BuildableFolderExceptions.from(
            manifest: manifest.exceptions,
            buildableFolder: path
        )
        let compilerFlagsByPath = Dictionary(uniqueKeysWithValues: exceptions.flatMap(\.compilerFlags))

        let allPaths = try await fileSystem
            .glob(directory: path, include: ["**/*"]).collect()
            .sorted()

        let opaqueFolderExtensions: Set<String> = Set(
            Target.validResourceCompatibleFolderExtensions + Target.validSourceCompatibleFolderExtensions
        )

        var opaqueBundleRoots = Set<AbsolutePath>()

        let resolvedFiles = allPaths.compactMap { filePath -> BuildableFolderFile? in
            if exclusions.contains(filePath) { return nil }

            if opaqueBundleRoots.contains(where: { filePath.isDescendant(of: $0) }) {
                return nil
            }

            if let ext = filePath.extension, opaqueFolderExtensions.contains(ext) {
                opaqueBundleRoots.insert(filePath)
            }

            return BuildableFolderFile(
                path: filePath,
                compilerFlags: compilerFlagsByPath[filePath]
            )
        }

        return XcodeGraph.BuildableFolder(
            path: path,
            exceptions: exceptions,
            resolvedFiles: resolvedFiles
        )
    }
}
