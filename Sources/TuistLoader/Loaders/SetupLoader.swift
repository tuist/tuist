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

    /// Default constructor.
    public convenience init() {
        let upLinter = UpLinter()
        let manifestLoader = ManifestLoader()
        self.init(upLinter: upLinter, manifestLoader: manifestLoader)
    }

    /// Initializes the command with its arguments.
    ///
    /// - Parameters:
    ///   - upLinter: Linter for up commands.
    ///   - manifestLoader: Manifset loader instance to load the setup.
    init(upLinter: UpLinting,
         manifestLoader: ManifestLoading)
    {
        self.upLinter = upLinter
        self.manifestLoader = manifestLoader
    }

    /// It runs meet on each command if it is not met.
    ///
    /// - Parameter path: Path to the project.
    /// - Throws: An error if any of the commands exit unsuccessfully
    ///           or if there isn't a `Setup.swift` file within the project path.
    public func meet(at path: AbsolutePath) throws {
        let path = try lookupManifest(from: path)
        logger.info("Setting up the environment defined in \(path.appending(component: Manifest.setup.fileName).pathString)")
        let setup = try manifestLoader.loadSetup(at: path)
        try setup.map { command in upLinter.lint(up: command) }
            .flatMap { $0 }
            .printAndThrowIfNeeded()
        try setup.forEach { command in
            if try !command.isMet(projectPath: path) {
                logger.notice("Configuring \(command.name)", metadata: .subsection)
                try command.meet(projectPath: path)
            }
        }
    }

    /// It traverses up the directory hierarchy until it finds a Setup.swift file.
    /// - Parameter path: Path from where to do the lookup.
    private func lookupManifest(from path: AbsolutePath) throws -> AbsolutePath {
        let manfiestPath = path.appending(component: Manifest.setup.fileName)
        if FileHandler.shared.exists(manfiestPath) {
            return path
        } else if path != .root {
            return try lookupManifest(from: path.parentDirectory)
        } else {
            throw SetupLoaderError.setupNotFound(path)
        }
    }
}
