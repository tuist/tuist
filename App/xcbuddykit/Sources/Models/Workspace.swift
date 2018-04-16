import Foundation
import PathKit
import Unbox

class Workspace {
    var projects: [Path]

    init(projects: [Path]) {
        self.projects = projects
    }

    init(path: Path, manifestLoader: GraphManifestLoading) throws {
        let workspacePath = path + Constants.Manifest.workspace
        if !workspacePath.exists { throw GraphLoadingError.missingFile(workspacePath) }
        let json = try manifestLoader.load(path: workspacePath)
        let unboxer = try Unboxer(data: json)
        projects = try unboxer.unbox(key: "projects")
        try projects.forEach { try $0.assertRelative() }
    }
}
