import Basic
import Foundation
import SPMUtility
import TuistCore

/// Protocol that represents an entity that knows how to get the environment status
/// for a given project and configure it.
protocol SetupLoading {
    /// It runs meet on each command if it is not met.
    ///
    /// - Parameter path: Path to the project.
    /// - Throws: An error if any of the commands exit unsuccessfully.
    func meet(at path: AbsolutePath) throws
}

class SetupLoader: SetupLoading {
    /// Linter for up commands.
    private let upLinter: UpLinting

    /// Graph manifset loader instance to load the setup.
    private let graphManifestLoader: GraphManifestLoading

    convenience init() {
        let upLinter = UpLinter()
        let graphManifestLoader = GraphManifestLoader()
        self.init(upLinter: upLinter, graphManifestLoader: graphManifestLoader)
    }

    /// Initializes the command with its arguments.
    ///
    /// - Parameters:
    ///   - upLinter: Linter for up commands.
    ///   - graphManifestLoader: Graph manifset loader instance to load the setup.
    init(upLinter: UpLinting,
         graphManifestLoader: GraphManifestLoading) {
        self.upLinter = upLinter
        self.graphManifestLoader = graphManifestLoader
    }

    /// It runs meet on each command if it is not met.
    ///
    /// - Parameter path: Path to the project.
    /// - Throws: An error if any of the commands exit unsuccessfully
    ///           or if there isn't a `Setup.swift` file within the project path.
    func meet(at path: AbsolutePath) throws {
        let setup = try graphManifestLoader.loadSetup(at: path)
        try setup.map { command in upLinter.lint(up: command) }
            .flatMap { $0 }
            .printAndThrowIfNeeded()
        try setup.forEach { command in
            if try !command.isMet(projectPath: path) {
                Printer.shared.print(subsection: "Configuring \(command.name)")
                try command.meet(projectPath: path)
            }
        }
    }
}
