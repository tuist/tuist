import Basic
import Foundation
import TuistCore

/// Protocol that defines the interface of an up command.
protocol UpCommanding {
    /// Name of the command.
    var name: String { get }

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameter system: System instance to run commands on the shell.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    func isMet(system: Systeming) throws -> Bool

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - system: System instance to run commands on the shell.
    ///   - printer: Printer instance to output information to the user.
    /// - Throws: An error if any error is thrown while running it.
    func meet(system: Systeming, printer: Printing) throws
}

/// It represents a command that configures the environment for the project to work.
/// The steps to set up the project are usually specified in the project README.
/// With Tuist, that's not necessary anymore because you can define declaratively those steps
/// and developers can run them by executing 'tuist up'
class UpCommand: UpCommanding {
    /// Name of the command.
    let name: String

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameter system: System instance to run commands on the shell.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    func isMet(system _: Systeming) throws -> Bool {
        fatalError("This method should be overriden")
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - system: System instance to run commands on the shell.
    ///   - printer: Printer instance to output information to the user.
    /// - Throws: An error if any error is thrown while running it.
    func meet(system _: Systeming, printer _: Printing) throws {
        fatalError("This method should be overriden")
    }

    /// Initializes the up command with its attributes.
    ///
    /// - Parameter name: Command name.
    init(name: String) {
        self.name = name
    }

    /// Initializes and returns an up command given its dictionary representation.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the command representation.
    ///   - projectPath: Path to the folder that contains the project.
    ///   - fileHandler: File handler instance to interact with the file system.
    /// - Returns: Initialized command.
    /// - Throws: An error if the representation has an invalid format
    static func with(dictionary: JSON, projectPath: AbsolutePath, fileHandler: FileHandling) throws -> UpCommand? {
        let type: String = try dictionary.get("type")
        if type == "custom" {
            return try CustomCommand(dictionary: dictionary, projectPath: projectPath, fileHandler: fileHandler)
        } else if type == "homebrew" {
            return try HomebrewCommand(dictionary: dictionary, projectPath: projectPath, fileHandler: fileHandler)
        }
        return nil
    }

    /// Returns true if the given tool is installed in the system.
    ///
    /// - Parameters
    ///   - name: Name of the tool.
    ///   - system: System instance to run the which command.
    /// - Returns: True if homwebrew is installed in the system.
    fileprivate func toolInstalled(_ name: String, system: Systeming) -> Bool {
        return (try? system.which(name)) != nil
    }
}

/// Command that installs Homebrew and packages.
class HomebrewCommand: UpCommand, GraphInitiatable {
    /// Homebrew packages to be installed.
    let packages: [String]

    /// Initializes the Homebrew command.
    ///
    /// - Parameter packages: Packages to be installed.
    init(packages: [String]) {
        self.packages = packages
        super.init(name: "Homebrew")
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest. This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    ///   - fileHandler: File handler for any file operations like checking whether a file exists or not.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required init(dictionary: JSON, projectPath _: AbsolutePath, fileHandler _: FileHandling) throws {
        packages = try dictionary.get("packages")
        super.init(name: "Homebrew")
    }

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameter system: System instance to run commands on the shell.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    override func isMet(system: Systeming) throws -> Bool {
        let packagesInstalled = packages.reduce(true, { $0 && toolInstalled($1, system: system) })
        return toolInstalled("brew", system: system) && packagesInstalled
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - system: System instance to run commands on the shell.
    ///   - printer: Printer instance to output information to the user.
    /// - Throws: An error if any error is thrown while running it.
    override func meet(system: Systeming, printer: Printing) throws {
        if !toolInstalled("brew", system: system) {
            printer.print("Installing Homebrew")
            // TODO:
        }
        let nonInstalledPackages = packages.filter({ !toolInstalled($0, system: system) })
        try nonInstalledPackages.forEach { package in
            printer.print("Installing Homebrew package: \(package)")
            try system.popen("/usr/local/bin/brew", arguments: ["install", package], verbose: false, environment: System.userEnvironment)
        }
    }
}

/// Custom setup command defined by the user.
class CustomCommand: UpCommand, GraphInitiatable {
    /// Shell command that needs to be executed if the command is not met in the environment.
    let meet: [String]

    /// Shell command that should return a 0 exit status if the setup has already been done (e.g. which carthage).
    let isMet: [String]

    /// Initializes a custom command.
    ///
    /// - Parameters:
    ///   - name: Name of the command.
    ///   - meet: Shell command that needs to be executed if the command is not met in the environment.
    ///   - isMet: Shell command that should return a 0 exit status if the setup has already been done (e.g. which carthage).
    init(name: String,
         meet: [String],
         isMet: [String]) {
        self.meet = meet
        self.isMet = isMet
        super.init(name: name)
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest. This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    ///   - fileHandler: File handler for any file operations like checking whether a file exists or not.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required init(dictionary: JSON, projectPath _: AbsolutePath, fileHandler _: FileHandling) throws {
        isMet = try dictionary.get("is_met")
        meet = try dictionary.get("meet")
        super.init(name: try dictionary.get("name"))
    }
}
