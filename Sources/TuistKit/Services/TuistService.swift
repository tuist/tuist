import Foundation
import TuistSupport
import TuistPlugin
import TuistLoader

enum TuistServiceError: FatalError {
    case taskUnavailable
    
    var type: ErrorType {
        switch self {
        case .taskUnavailable:
            return .abortSilent
        }
    }
    
    var description: String {
        switch self {
        case .taskUnavailable:
            return "Task was not found in the environment"
        }
    }
}

final class TuistService: NSObject {
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading
    
    init(
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: CachedManifestLoader())
    ) {
        self.pluginService = pluginService
        self.configLoader = configLoader
    }
    
    func run(_ arguments: [String]) throws {
        var arguments = arguments

        let commandName = "tuist-\(arguments[0])"
        
        let config = try configLoader.loadConfig(path: FileHandler.shared.currentPath)
        let pluginExecutables = try pluginService.remotePluginPaths(using: config)
            .compactMap(\.releasePath)
            .flatMap(FileHandler.shared.contentsOfDirectory)
            .filter { $0.basename.hasPrefix("tuist-") }
        if let pluginCommand = pluginExecutables.first(where: { $0.basename == commandName }) {
            arguments[0] = pluginCommand.pathString
        } else if System.shared.commandExists(commandName) {
            arguments[0] = commandName
        } else {
            throw TuistServiceError.taskUnavailable
        }

        try System.shared.runAndPrint(arguments)
    }
}
