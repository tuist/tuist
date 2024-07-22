import Foundation
import Path
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
        let projectPath: Path.AbsolutePath
        if let path {
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
            encoded = try await manifestLoader.loadProject(at: projectPath)
        case .workspace:
            encoded = try await manifestLoader.loadWorkspace(at: projectPath)
        case .config:
            encoded = try await manifestLoader.loadConfig(at: projectPath.appending(component: Constants.tuistDirectoryName))
        case .template:
            encoded = try await manifestLoader.loadTemplate(at: projectPath)
        case .plugin:
            encoded = try await manifestLoader.loadPlugin(at: projectPath)
        case .package:
            encoded = try await manifestLoader.loadPackageSettings(at: projectPath)
        }

        let json: JSON = try encoded.toJSON()
        logger.notice("\(json.toString(prettyPrint: true))", metadata: .json)
    }
}

enum DumpableManifest: String, CaseIterable {
    case project
    case workspace
    case config
    case template
    case plugin
    case package
}
