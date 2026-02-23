import FileSystem
import Foundation
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

        let exceptions = try await XcodeGraph.BuildableFolderExceptions.from(
            manifest: manifest.exceptions,
            buildableFolder: path,
            fileSystem: fileSystem
        )
        let exclusions = Set(exceptions.flatMap(\.excluded))
        let compilerFlagsByPath = Dictionary(uniqueKeysWithValues: exceptions.flatMap(\.compilerFlags))

        let resolvedFiles = try await fileSystem
            .glob(directory: path, include: ["**/*"]).collect()
            .compactMap { path -> BuildableFolderFile? in
                if exclusions.contains(path) { return nil }
                return BuildableFolderFile(
                    path: path,
                    compilerFlags: compilerFlagsByPath[path]
                )
            }

        return XcodeGraph.BuildableFolder(
            path: path,
            exceptions: exceptions,
            resolvedFiles: resolvedFiles
        )
    }
}
