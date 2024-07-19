import Foundation
import Path
import TuistCore
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistSupport
import XcodeGraph

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
    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring

    init(
        projectEditor: ProjectEditing = ProjectEditor(),
        opener: Opening = Opener(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        pluginService: PluginServicing = PluginService(),
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring = CacheDirectoriesProviderFactory()
    ) {
        self.projectEditor = projectEditor
        self.opener = opener
        self.configLoader = configLoader
        self.pluginService = pluginService
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
    }

    func run(
        path: String?,
        permanent: Bool,
        onlyCurrentDirectory: Bool
    ) async throws {
        let path = try self.path(path)
        let plugins = await loadPlugins(at: path)

        if !permanent {
            let cacheDirectoryProvider = try cacheDirectoryProviderFactory.cacheDirectories()
            let cacheDirectory = try cacheDirectoryProvider.cacheDirectory(for: .editProjects)
            let cachedManifestDirectory = cacheDirectory.appending(component: path.pathString.md5)

            guard let selectedXcode = try XcodeController.shared.selected() else {
                throw EditServiceError.xcodeNotSelected
            }

            let workspacePath = try await projectEditor.edit(
                at: path,
                in: cachedManifestDirectory,
                onlyCurrentDirectory: onlyCurrentDirectory,
                plugins: plugins
            )
            logger.notice("Opening Xcode to edit the project.", metadata: .pretty)
            try opener.open(path: workspacePath, application: selectedXcode.path, wait: false)

        } else {
            let workspacePath = try await projectEditor.edit(
                at: path,
                in: path,
                onlyCurrentDirectory: onlyCurrentDirectory,
                plugins: plugins
            )
            logger.notice("Xcode project generated at \(workspacePath.pathString)", metadata: .success)
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
            logger.warning("Unable to load Config.swift, fix any compiler errors and re-run for plugins to be loaded.")
            return .none
        }

        guard let plugins = try? await pluginService.loadPlugins(using: config) else {
            logger.warning("Unable to load Plugin.swift manifest, fix and re-run in order to use plugin(s).")
            return .none
        }

        return plugins
    }
}
