import Foundation
import Path
import ServiceContextModule
import TuistCore
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistSupport

enum EditServiceError: FatalError {
    case xcodeNotSelected

    var description: String {
        switch self {
        case .xcodeNotSelected:
            return "Couldn't determine the Xcode version to open the project. Make sure your Xcode installation is selected with 'xcode-select -s'."
        }
    }

    var type: ErrorType {
        switch self {
        case .xcodeNotSelected:
            return .abort
        }
    }
}

final class EditService {
    private let projectEditor: ProjectEditing
    private let opener: Opening
    private let configLoader: ConfigLoading
    private let pluginService: PluginServicing
    private let cacheDirectoriesProvider: CacheDirectoriesProviding

    init(
        projectEditor: ProjectEditing = ProjectEditor(),
        opener: Opening = Opener(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        pluginService: PluginServicing = PluginService(),
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider()
    ) {
        self.projectEditor = projectEditor
        self.opener = opener
        self.configLoader = configLoader
        self.pluginService = pluginService
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
    }

    func run(
        path: String?,
        permanent: Bool,
        onlyCurrentDirectory: Bool
    ) async throws {
        let path = try self.path(path)
        let plugins = await loadPlugins(at: path)

        if !permanent {
            let cacheDirectory = try cacheDirectoriesProvider.cacheDirectory(for: .editProjects)
            let cachedManifestDirectory = cacheDirectory.appending(component: path.pathString.md5)

            let selectedXcode = try await XcodeController.shared.selected()
            let workspacePath = try await projectEditor.edit(
                at: path,
                in: cachedManifestDirectory,
                onlyCurrentDirectory: onlyCurrentDirectory,
                plugins: plugins
            )
            ServiceContext.current?.logger?.notice("Opening Xcode to edit the project.", metadata: .pretty)
            try opener.open(path: workspacePath, application: selectedXcode.path, wait: false)

        } else {
            let workspacePath = try await projectEditor.edit(
                at: path,
                in: path,
                onlyCurrentDirectory: onlyCurrentDirectory,
                plugins: plugins
            )
            ServiceContext.current?.alerts?.append(.success(.alert("Xcode project generated at \(workspacePath.pathString)")))
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func loadPlugins(at path: AbsolutePath) async -> Plugins {
        guard let config = try? await configLoader.loadConfig(path: path) else {
            ServiceContext.current?.logger?
                .warning(
                    "Unable to load \(Constants.tuistManifestFileName), fix any compiler errors and re-run for plugins to be loaded."
                )
            return .none
        }

        guard let plugins = try? await pluginService.loadPlugins(using: config) else {
            ServiceContext.current?.logger?
                .warning("Unable to load Plugin.swift manifest, fix and re-run in order to use plugin(s).")
            return .none
        }

        return plugins
    }
}
