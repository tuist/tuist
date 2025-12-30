import Foundation
import Path
import TSCBasic
import TuistCore
import TuistLoader
import TuistPlugin
import TuistSupport

final class DumpService {
    private let manifestLoader: ManifestLoading
    private let configLoader: ConfigLoading

    convenience init() {
        let manifestLoader = CachedManifestLoader()
        let configLoader = ConfigLoader(manifestLoader: manifestLoader)
        self.init(
            manifestLoader: manifestLoader,
            configLoader: configLoader
        )
    }

    init(
        manifestLoader: ManifestLoading,
        configLoader: ConfigLoading
    ) {
        self.manifestLoader = manifestLoader
        self.configLoader = configLoader
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
            let config = try await configLoader.loadConfig(path: projectPath)
            encoded = try await manifestLoader.loadProject(
                at: projectPath,
                disableSandbox: config.project.disableSandbox
            )
        case .workspace:
            let config = try await configLoader.loadConfig(path: projectPath)
            encoded = try await manifestLoader.loadWorkspace(
                at: projectPath,
                disableSandbox: config.project.disableSandbox
            )
        case .config:
            encoded = try await manifestLoader.loadConfig(at: projectPath)
        case .template:
            encoded = try await manifestLoader.loadTemplate(at: projectPath)
        case .plugin:
            encoded = try await manifestLoader.loadPlugin(at: projectPath)
        case .package:
            let config = try await configLoader.loadConfig(path: projectPath)
            encoded = try await manifestLoader.loadPackageSettings(
                at: projectPath,
                disableSandbox: config.project.disableSandbox
            )
        }

        let json: JSON = try encoded.toJSON()
        Logger.current.notice("\(json.toString(prettyPrint: true))", metadata: .json)
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
