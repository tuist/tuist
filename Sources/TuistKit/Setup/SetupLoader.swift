import Basic
import Foundation
import TuistCore
import Utility

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
    fileprivate let upLinter: UpLinting

    /// File handler instance to interact with the file system.
    fileprivate let fileHandler: FileHandling

    /// Printer instance to output information to the user.
    fileprivate let printer: Printing

    /// Graph manifset loader instance to load the setup.
    fileprivate let graphManifestLoader: GraphManifestLoading

    /// System instance to run commands on the system.
    fileprivate let system: Systeming

    convenience init(fileHandler: FileHandling = FileHandler()) {
        let upLinter = UpLinter()
        let graphManifestLoader = GraphManifestLoader()
        self.init(upLinter: upLinter,
                  fileHandler: fileHandler,
                  printer: Printer(),
                  graphManifestLoader: graphManifestLoader,
                  system: System())
    }

    /// Initializes the command with its arguments.
    ///
    /// - Parameters:
    ///   - upLinter: Linter for up commands.
    ///   - fileHandler: File handler instance to interact with the file system.
    ///   - printer: Printer instance to output information to the user.
    ///   - graphManifestLoader: Graph manifset loader instance to load the setup.
    ///   - system: System instance to run commands on the system.
    init(upLinter: UpLinting,
         fileHandler: FileHandling,
         printer: Printing,
         graphManifestLoader: GraphManifestLoading,
         system: Systeming) {
        self.upLinter = upLinter
        self.fileHandler = fileHandler
        self.printer = printer
        self.graphManifestLoader = graphManifestLoader
        self.system = system
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
            .printAndThrowIfNeeded(printer: printer)
        try setup.forEach { command in
            if try !command.isMet(system: system, projectPath: path) {
                printer.print(subsection: "Configuring \(command.name)")
                try command.meet(system: system, printer: printer, projectPath: path)
            }
        }
    }
}
