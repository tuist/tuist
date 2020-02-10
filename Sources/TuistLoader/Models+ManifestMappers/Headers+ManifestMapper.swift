import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.Headers {
    static func from(manifest: ProjectDescription.Headers,
                     path _: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.Headers {
        let `public` = try manifest.public?.globs.flatMap {
            headerFiles(try generatorPaths.resolve(path: $0))
        } ?? []

        let `private` = try manifest.private?.globs.flatMap {
            headerFiles(try generatorPaths.resolve(path: $0))
        } ?? []

        let project = try manifest.project?.globs.flatMap {
            headerFiles(try generatorPaths.resolve(path: $0))
        } ?? []

        return Headers(public: `public`, private: `private`, project: project)
    }

    private static func headerFiles(_ path: AbsolutePath) -> [AbsolutePath] {
        FileHandler.shared.glob(AbsolutePath("/"), glob: String(path.pathString.dropFirst())).filter {
            if let `extension` = $0.extension, Headers.extensions.contains(".\(`extension`)") {
                return true
            }
            return false
        }
    }
}
