import Foundation
import Path
import ProjectDescription
import TuistSupport
import XcodeGraph

extension FileListGlob {
    func unfold(
        generatorPaths: GeneratorPaths,
        filter: ((AbsolutePath) -> Bool)? = nil
    ) throws -> [AbsolutePath] {
        if glob.pathString.contains("$") {
            return [try generatorPaths.resolve(path: glob)]
        }

        let resolvedPath = try generatorPaths.resolve(path: glob)
        let resolvedExcluding = try resolvedExcluding(generatorPaths: generatorPaths)
        let pattern = String(resolvedPath.pathString.dropFirst())

        return FileHandler.shared.glob(AbsolutePath.root, glob: pattern).filter { path in
            guard !resolvedExcluding.contains(path) else {
                return false
            }
            if let filter {
                return filter(path)
            }
            return true
        }
    }

    private func resolvedExcluding(generatorPaths: GeneratorPaths) throws -> Set<AbsolutePath> {
        guard !excluding.isEmpty else { return [] }
        var result: Set<AbsolutePath> = []
        for path in excluding {
            let resolved = try generatorPaths.resolve(path: path)
            let globs = try AbsolutePath(validating: resolved.dirname).glob(resolved.basename)
            result.formUnion(globs)
        }
        return result
    }
}
