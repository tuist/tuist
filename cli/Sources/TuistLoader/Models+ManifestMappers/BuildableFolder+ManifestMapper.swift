import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistLogging
import XcodeGraph

enum BuildableFolderManifestMapperError: FatalError, Equatable {
    case folderNotFound(targetName: String, path: AbsolutePath)

    var type: ErrorType { .abort }

    var description: String {
        switch self {
        case let .folderNotFound(targetName: targetName, path: path):
            return "The target \(targetName) has a buildableFolder at \(path.pathString) that does not exist."
        }
    }
}

extension XcodeGraph.BuildableFolder {
    static func from(
        manifest: ProjectDescription.BuildableFolder,
        generatorPaths: GeneratorPaths,
        targetName: String
    ) async throws -> XcodeGraph.BuildableFolder {
        let path = try generatorPaths.resolve(path: manifest.path)
        let fileSystem = FileSystem()

        if try await !fileSystem.exists(path) {
            throw BuildableFolderManifestMapperError.folderNotFound(targetName: targetName, path: path)
        }

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
