import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.Headers: ModelConvertible {
    init(manifest: ProjectDescription.Headers, generatorPaths: GeneratorPaths) throws {
        let `public` = try manifest.public?.globs.flatMap {
            TuistCore.Headers.headerFiles(try generatorPaths.resolve(path: $0))
        } ?? []

        let `private` = try manifest.private?.globs.flatMap {
            TuistCore.Headers.headerFiles(try generatorPaths.resolve(path: $0))
        } ?? []

        let project = try manifest.project?.globs.flatMap {
            TuistCore.Headers.headerFiles(try generatorPaths.resolve(path: $0))
        } ?? []
        self.init(public: `public`, private: `private`, project: project)
    }

    /// This method unfolds glob patterns and filters out files that are not valid as header files.
    /// - Parameter path: Glob pattern to be unfolded.
    fileprivate static func headerFiles(_ path: AbsolutePath) -> [AbsolutePath] {
        FileHandler.shared.glob(AbsolutePath("/"), glob: String(path.pathString.dropFirst())).filter {
            // Filters out those headers that are not valid header files.
            if let `extension` = $0.extension, Headers.extensions.contains(".\(`extension`)") {
                return true
            }
            return false
        }
    }
}
