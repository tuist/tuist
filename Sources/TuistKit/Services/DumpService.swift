import Foundation
import Basic
import TuistLoader
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
        let project = try manifestLoader.loadProject(at: projectPath)
        let json: JSON = try project.toJSON()
        logger.notice("\(json.toString(prettyPrint: true))")
    }
}
