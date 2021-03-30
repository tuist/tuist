import Foundation
import TSCBasic
import TuistCore
import TuistLoader
import TuistPlugin
import TuistSupport

final class DumpService {
    private let manifestLoader: ManifestLoading

    init(manifestLoader: ManifestLoading = ManifestLoader()) {
        self.manifestLoader = manifestLoader
    }

    func run(path: String?) throws {
        let projectPath: AbsolutePath
        if let path = path {
            projectPath = AbsolutePath(path, relativeTo: AbsolutePath.current)
        } else {
            projectPath = AbsolutePath.current
        }
        let manifestGraphLoader = ManifestGraphLoader(manifestLoader: manifestLoader)
        try manifestGraphLoader.loadPlugins(at: projectPath)
        let project = try manifestLoader.loadProject(at: projectPath)
        let json: JSON = try project.toJSON()
        logger.notice("\(json.toString(prettyPrint: true))")
    }
}
