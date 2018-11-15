import Basic
import Foundation
import TuistCore

/// Protocol that defines the interface of an up command.
protocol Upping {
    /// Name of the command.
    var name: String { get }

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameters
    ///   - system: System instance to run commands on the shell.
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    func isMet(system: Systeming, projectPath: AbsolutePath) throws -> Bool

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - system: System instance to run commands on the shell.
    ///   - printer: Printer instance to output information to the user.
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    func meet(system: Systeming, printer: Printing, projectPath: AbsolutePath) throws
}

/// It represents a command that configures the environment for the project to work.
/// The steps to set up the project are usually specified in the project README.
/// With Tuist, that's not necessary anymore because you can define declaratively those steps
/// and developers can run them by executing 'tuist up'
class Up: Upping {
    /// Name of the command.
    let name: String

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameters
    ///   - system: System instance to run commands on the shell.
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    func isMet(system _: Systeming, projectPath _: AbsolutePath) throws -> Bool {
        fatalError("This method should be overriden")
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - system: System instance to run commands on the shell.
    ///   - printer: Printer instance to output information to the user.
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    func meet(system _: Systeming, printer _: Printing, projectPath _: AbsolutePath) throws {
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
    static func with(dictionary: JSON, projectPath: AbsolutePath, fileHandler: FileHandling) throws -> Up? {
        let type: String = try dictionary.get("type")
        if type == "custom" {
            return try UpCustom(dictionary: dictionary, projectPath: projectPath, fileHandler: fileHandler)
        } else if type == "homebrew" {
            return try UpHomebrew(dictionary: dictionary, projectPath: projectPath, fileHandler: fileHandler)
        } else if type == "carthage" {
            return try UpCarthage(dictionary: dictionary, projectPath: projectPath, fileHandler: fileHandler)
        } else if type == "yarn" {
            return try UpYarn(dictionary: dictionary, projectPath: projectPath, fileHandler: fileHandler)
        }
        return nil
    }

    /// Returns true if the given tool is installed in the system.
    ///
    /// - Parameters
    ///   - name: Name of the tool.
    ///   - system: System instance to run the which command.
    /// - Returns: True if homwebrew is installed in the system.
    func toolInstalled(_ name: String, system: Systeming) -> Bool {
        return (try? system.which(name)) != nil
    }
}
