import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistSupport

extension FileListGlob {
    func unfold(
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming,
        filter: ((AbsolutePath) -> Bool)? = nil
    ) async throws -> [AbsolutePath] {
        if glob.pathString.contains("$") {
            return [try generatorPaths.resolve(path: glob)]
        }

        let resolvedPath = try generatorPaths.resolve(path: glob)
        let resolvedExcluding = try await resolvedExcluding(
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )
        let pattern = String(resolvedPath.pathString.dropFirst())

        return try await fileSystem.glob(directory: AbsolutePath.root, include: [pattern]).collect().filter { path in
            guard !resolvedExcluding.contains(path) else {
                return false
            }
            if let filter {
                return filter(path)
            }
            return true
        }
    }

    private func resolvedExcluding(
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming
    ) async throws -> Set<AbsolutePath> {
        guard !excluding.isEmpty else { return [] }
        var result: Set<AbsolutePath> = []
        for path in excluding {
            let resolved = try generatorPaths.resolve(path: path)
            let globs = try await fileSystem.glob(
                directory: .root,
                include: [String(resolved.pathString.dropFirst())]
            )
            .collect()
            result.formUnion(globs)
        }
        return result
    }
}
