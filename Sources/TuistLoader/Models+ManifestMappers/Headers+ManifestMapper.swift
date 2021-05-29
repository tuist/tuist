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
        let unfoldGlob: (AbsolutePath) -> [AbsolutePath] = { path in
            FileHandler.shared.glob(AbsolutePath.root, glob: String(path.pathString.dropFirst())).filter {
                if let fileExtension = $0.extension {
                    return TuistGraph.Headers.extensions.contains(".\(fileExtension)")
                }
                return false
            }
        }

        let `public` = try manifest.public?.globs.flatMap {
            unfoldGlob(try generatorPaths.resolve(path: $0))
        } ?? []

        let `private` = try manifest.private?.globs.flatMap {
            unfoldGlob(try generatorPaths.resolve(path: $0))
        } ?? []

        let project = try manifest.project?.globs.flatMap {
            unfoldGlob(try generatorPaths.resolve(path: $0))
        } ?? []

        return Headers(public: `public`, private: `private`, project: project)
    }
}
