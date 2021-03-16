import Foundation
import Signals
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

    private static var temporaryDirectory: AbsolutePath?

    init(
        projectEditor: ProjectEditing = ProjectEditor(),
        opener: Opening = Opener(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        pluginService: PluginServicing = PluginService()
    ) {
        self.projectEditor = projectEditor
        self.opener = opener
        self.configLoader = configLoader
        self.pluginService = pluginService
    }

    func run(path: String?,
             permanent: Bool,
             onlyCurrentDirectory _: Bool) throws
    {
        let path = self.path(path)

        if !permanent {
            try withTemporaryDirectory(removeTreeOnDeinit: true) { generationDirectory in
                EditService.temporaryDirectory = generationDirectory

                Signals.trap(signals: [.int, .abrt]) { _ in
                    // swiftlint:disable:next force_try
                    try! EditService.temporaryDirectory.map(FileHandler.shared.delete)
                    exit(0)
                }

                guard let selectedXcode = try XcodeController.shared.selected() else {
                    throw EditServiceError.xcodeNotSelected
                }

                let plugins = loadPlugins(at: path)
                let workspacePath = try projectEditor.edit(at: path, in: generationDirectory, plugins: plugins)
                logger.pretty("Opening Xcode to edit the project. Press \(.keystroke("CTRL + C")) once you are done editing")
                try opener.open(path: workspacePath, application: selectedXcode.path, wait: true)
            }
        } else {
            let plugins = loadPlugins(at: path)
            let workspacePath = try projectEditor.edit(at: path, in: path, plugins: plugins)
            logger.notice("Xcode project generated at \(workspacePath.pathString)", metadata: .success)
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func loadPlugins(at path: AbsolutePath) -> Plugins {
        guard let config = try? configLoader.loadConfig(path: path) else {
            logger.warning("Unable to load Config.swift, fix any compiler errors and re-run for plugins to be loaded.")
            return .none
        }

        guard let plugins = try? pluginService.loadPlugins(using: config) else {
            logger.warning("Unable to load Plugin.swift manifest, fix and re-run in order to use plugin(s).")
            return .none
        }

        return plugins
    }
}
