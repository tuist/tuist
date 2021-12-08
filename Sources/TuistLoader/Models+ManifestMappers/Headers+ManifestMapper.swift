import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Headers {
    /// Maps a ProjectDescription.Headers instance into a TuistGraph.Headers model.
    /// Glob patterns are resolved as part of the mapping process.
    /// - Parameters:
    ///   - manifest: Manifest representation of Headers.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Headers, generatorPaths: GeneratorPaths) throws -> TuistGraph.Headers {
        func resolveExcluding(_ excluding: [Path]?) throws -> Set<AbsolutePath> {
            guard let excluding = excluding else { return [] }
            var result: Set<AbsolutePath> = []
            try excluding.forEach { path in
                let resolved = try generatorPaths.resolve(path: path).pathString
                let absolute = AbsolutePath(resolved)
                let globs = AbsolutePath(absolute.dirname).glob(absolute.basename)
                result.formUnion(globs)
            }
            return result
        }

        func unfoldGlob(_ path: AbsolutePath, excluding: Set<AbsolutePath>) -> [AbsolutePath] {
            FileHandler.shared.glob(AbsolutePath.root, glob: String(path.pathString.dropFirst())).filter {
                guard let fileExtension = $0.extension else {
                    return false
                }
                return TuistGraph.Headers.extensions.contains(".\(fileExtension)") && !excluding.contains($0)
            }
        }

        var autoExlcudedPaths = Set<AbsolutePath>()
        let `public`: [AbsolutePath]
        let `private`: [AbsolutePath]
        let project: [AbsolutePath]

        func resolveHeaders(_ list: FileList?) throws -> [AbsolutePath] {
            guard let list = list else { return [] }
            return try list.globs.flatMap {
                unfoldGlob(
                    try generatorPaths.resolve(path: $0.glob),
                    excluding: (try resolveExcluding($0.excluding)).union(autoExlcudedPaths)
                )
            }
        }

        switch manifest.exclusionRule {
        case .none:
            `public` = try resolveHeaders(manifest.public)
            `private` = try resolveHeaders(manifest.private)
            project = try resolveHeaders(manifest.project)
            
        case .projectExcludesPrivateAndPublic:
            `public` = try resolveHeaders(manifest.public)
            autoExlcudedPaths.formUnion(`public`)
            `private` = try resolveHeaders(manifest.private)
            autoExlcudedPaths.formUnion(`private`)
            project = try resolveHeaders(manifest.project)

        case .publicExcludesPrivateAndProject:
            project = try resolveHeaders(manifest.project)
            autoExlcudedPaths.formUnion(project)
            `private` = try resolveHeaders(manifest.private)
            autoExlcudedPaths.formUnion(`private`)
            `public` = try resolveHeaders(manifest.public)
        }
        
        return Headers(public: `public`, private: `private`, project: project)
    }
}
