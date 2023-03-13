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

    func run(path: String?, manifest: DumpableManifest) async throws {
        let projectPath: AbsolutePath
        if let path = path {
            projectPath = try AbsolutePath(validating: path, relativeTo: AbsolutePath.current)
        } else {
            projectPath = AbsolutePath.current
        }

        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        try await manifestGraphLoader.loadPlugins(at: projectPath)

        let encoded: Encodable
        switch manifest {
        case .project:
            encoded = try manifestLoader.loadProject(at: projectPath)
        case .workspace:
            encoded = try manifestLoader.loadWorkspace(at: projectPath)
        case .config:
            encoded = try manifestLoader.loadConfig(at: projectPath.appending(component: Constants.tuistDirectoryName))
        case .template:
            encoded = try manifestLoader.loadTemplate(at: projectPath)
        case .dependencies:
            encoded = try manifestLoader.loadDependencies(at: projectPath)
        case .plugin:
            encoded = try manifestLoader.loadPlugin(at: projectPath)
        }

        let json: JSON = try encoded.toJSON()
        logger.notice("\(json.toString(prettyPrint: true))")
    }
}

enum DumpableManifest: String, CaseIterable {
    case project
    case workspace
    case config
    case template
    case dependencies
    case plugin
}
