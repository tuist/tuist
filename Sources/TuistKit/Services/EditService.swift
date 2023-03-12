import Foundation
import TSCBasic
import TuistGenerator
import TuistGraph
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
    private let signalHandler: SignalHandling

    private static var temporaryDirectory: AbsolutePath?

    init(
        projectEditor: ProjectEditing = ProjectEditor(),
        opener: Opening = Opener(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        pluginService: PluginServicing = PluginService(),
        signalHandler: SignalHandling = SignalHandler()
    ) {
        self.projectEditor = projectEditor
        self.opener = opener
        self.configLoader = configLoader
        self.pluginService = pluginService
        self.signalHandler = signalHandler
    }

    func run(
        path: String?,
        permanent: Bool,
        onlyCurrentDirectory: Bool
    ) async throws {
        let path = try self.path(path)
        let plugins = await loadPlugins(at: path)

        if !permanent {
            try withTemporaryDirectory(removeTreeOnDeinit: true) { generationDirectory in
                EditService.temporaryDirectory = generationDirectory

                signalHandler.trap { _ in
                    try? EditService.temporaryDirectory.map(FileHandler.shared.delete)
                    exit(0)
                }

                guard let selectedXcode = try XcodeController.shared.selected() else {
                    throw EditServiceError.xcodeNotSelected
                }

                let workspacePath = try projectEditor.edit(
                    at: path,
                    in: generationDirectory,
                    onlyCurrentDirectory: onlyCurrentDirectory,
                    plugins: plugins
                )
                logger.pretty("Opening Xcode to edit the project. Press \(.keystroke("CTRL + C")) once you are done editing")
                try opener.open(path: workspacePath, application: selectedXcode.path, wait: true)
            }
        } else {
            let workspacePath = try projectEditor.edit(
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
        if let path = path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func loadPlugins(at path: AbsolutePath) async -> Plugins {
        guard let config = try? configLoader.loadConfig(path: path) else {
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
