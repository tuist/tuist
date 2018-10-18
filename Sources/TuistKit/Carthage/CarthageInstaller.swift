import Foundation
import TuistCore
import Basic

protocol CarthageInstalling: AnyObject {
    func install(graph: Graph) throws
}

/// Errors thrown installing Carthage
enum CarthageInstallerError: FatalError {
    case carthageNotFound
    
    var type: ErrorType {
        switch self {
        case .carthageNotFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case .carthageNotFound:
            return "Carthage was not found in your system"
        }
    }
}

class CarthageInstaller: CarthageInstalling {
    
    // MARK: - Attributes
    
    /// System instance to run commands.
    private let system: Systeming
    
    /// File handler instance for file operations.
    private let fileHandler: FileHandling
    
    /// Printer to output messages to the user.
    private let printer: Printing
    
    // MARK: - Init
    
    /// Default installer constructor.
    ///
    /// - Parameter system: System instance to run commands.
    /// - Parameter fileHandler: File handler instance for file operations.
    /// - Parameter printer: Printer to output messages to the user.
    init(system: Systeming = System(),
         fileHandler: FileHandling = FileHandler(),
         printer: Printing = Printer()) {
        self.system = system
        self.fileHandler = fileHandler
        self.printer = printer
    }
    
    func install(graph: Graph) throws {
        let carthageFrameworks = graph.frameworks.filter({ $0.isCarthage })
        var carthagePaths: Set<AbsolutePath> = Set()
        try carthagePaths.formUnion(cartfilePathsFromOutdatedFrameworks(frameworks: carthageFrameworks))
        carthagePaths.formUnion(cartfilePathsFromMissingFrameworks(frameworks: carthageFrameworks))
        if carthagePaths.isEmpty { return }
        try verifyCarthageExists()
        try install(paths: carthagePaths)
    }
    
    // MARK: - Fileprivate
    
    /// Verifies if Carthage exists by throwing if it's not found in the system.
    ///
    /// - Throws: CarthageInstallerError.carthageNotFound if Carthage is not found.
    fileprivate func verifyCarthageExists() throws {
        do {
            _ = try system.which("carthage")
        } catch is SystemError {
            throw CarthageInstallerError.carthageNotFound
        }
    }
    
    fileprivate func cartfilePathsFromOutdatedFrameworks(frameworks: [FrameworkNode]) throws -> [AbsolutePath] {
        return try frameworks
            .map(cartfilePath)
            .filter { path in
                try system.capture("/usr/bin/env",
                                   arguments: ["carthage", "validate", "--project-directory", path.asString],
                                   verbose: false,
                                   environment: System.userEnvironment).exitcode != 0
        }
    }
    
    /// It returns a list of directories what have references to missing Carthage dependencies.
    ///
    /// - Parameter frameworks: List of frameworks that the graph projects depend on.
    /// - Returns: Lit of directories that have references to missing Carthage dependencies.
    fileprivate func cartfilePathsFromMissingFrameworks(frameworks: [FrameworkNode]) -> [AbsolutePath] {
        return frameworks
            .filter({ !fileHandler.exists($0.path) })
            .map(cartfilePath)
    }
    
    /// Runs "carthage update" on the given paths.
    ///
    /// - Parameter paths: List of paths with Cartfiles where we need to run "carthage update".
    /// - Throws: An error if the update process fails.
    fileprivate func install(paths: Set<AbsolutePath>) throws {
        printer.print(section: "Installing missing or outdated Carthage dependencies")
        try paths.forEach { path in
            printer.print("Updating dependencies in directory \(path)")
            try system.popen("/usr/bin/env",
                             arguments: ["carthage", "update", "--project-directory", path.asString],
                             verbose: false,
                             environment: System.userEnvironment)
        }
    }
    
    /// Given a Carthage framework it returns the folder that contains the Cartfile.
    ///
    /// - Parameter framework: Carthage framework.
    /// - Returns: Directory that contains the Cartfile where the framework is defined.
    fileprivate func cartfilePath(from framework: FrameworkNode) -> AbsolutePath {
        return framework.path.parentDirectory.parentDirectory.parentDirectory.parentDirectory
    }
    
}
