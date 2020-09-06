import Foundation
import TSCBasic
import TuistSupport

enum SetupLoaderError: FatalError {
    case setupNotFound(AbsolutePath)

    var description: String {
        switch self {
        case let .setupNotFound(path):
            return "We couldn't find a Setup.swift traversing up the directory hierarchy from the path \(path.pathString)."
        }
    }

    var type: ErrorType {
        switch self {
        case .setupNotFound: return .abort
        }
    }
}

/// Protocol that represents an entity that knows how to get the environment status
/// for a given project and configure it.
public protocol SetupLoading {
    /// It runs meet on each command if it is not met.
    ///
    /// - Parameter path: Path to the project.
    /// - Throws: An error if any of the commands exit unsuccessfully.
    func meet(at path: AbsolutePath) throws
}

public class SetupLoader: SetupLoading {
    /// Linter for up commands.
    private let upLinter: UpLinting

    /// Manifset loader instance to load the setup.
    private let manifestLoader: ManifestLoading
    
    /// Locator for `Setup.swift` file
    private let setupLocator: SetupLocating

    /// Default constructor.
    public convenience init() {
        let upLinter = UpLinter()
        let manifestLoader = ManifestLoader()
        let setupLocator = SetupLocator()
        self.init(upLinter: upLinter, manifestLoader: manifestLoader, setupLocator: setupLocator)
    }

    /// Initializes the command with its arguments.
    ///
    /// - Parameters:
    ///   - upLinter: Linter for up commands.
    ///   - manifestLoader: Manifset loader instance to load the setup.
    ///   - setupLocator: Locator for `Setup.swift` file
    init(upLinter: UpLinting,
         manifestLoader: ManifestLoading,
         setupLocator: SetupLocating)
    {
        self.upLinter = upLinter
        self.manifestLoader = manifestLoader
        self.setupLocator = setupLocator
    }

    /// It runs meet on each command if it is not met.
    ///
    /// - Parameter path: Path to the project.
    /// - Throws: An error if any of the commands exit unsuccessfully
    ///           or if there isn't a `Setup.swift` file within the project path.
    public func meet(at path: AbsolutePath) throws {
        guard let setupPath = setupLocator.locate(at: path) else { throw SetupLoaderError.setupNotFound(path) }
        logger.info("Setting up the environment defined in \(setupPath).pathString)")
        
        let setupParentPath = setupPath.parentDirectory
        
        let setup = try manifestLoader.loadSetup(at: setupParentPath)
        try setup.map { command in upLinter.lint(up: command) }
            .flatMap { $0 }
            .printAndThrowIfNeeded()
        try setup.forEach { command in
            if try !command.isMet(projectPath: setupParentPath) {
                logger.notice("Configuring \(command.name)", metadata: .subsection)
                try command.meet(projectPath: setupParentPath)
            }
        }
    }
}
