import Foundation
import TSCBasic
import TuistSupport

/// Protocol that defines the interface of an up command.
public protocol Upping: AnyObject {
    /// Name of the command.
    var name: String { get }

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameters
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    func isMet(projectPath: AbsolutePath) throws -> Bool

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    func meet(projectPath: AbsolutePath) throws
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
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    func isMet(projectPath _: AbsolutePath) throws -> Bool {
        fatalError("This method should be overriden")
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    func meet(projectPath _: AbsolutePath) throws {
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
    /// - Returns: Initialized command.
    /// - Throws: An error if the representation has an invalid format
    static func with(dictionary: JSON, projectPath: AbsolutePath) throws -> Up? {
        let type: String = try dictionary.get("type")
        if type == "custom" {
            return try UpCustom(dictionary: dictionary, projectPath: projectPath)
        } else if type == "homebrew" {
            return try UpHomebrew(dictionary: dictionary, projectPath: projectPath)
        } else if type == "homebrew-tap" {
            return try UpHomebrewTap(dictionary: dictionary, projectPath: projectPath)
        } else if type == "carthage" {
            return try UpCarthage(dictionary: dictionary, projectPath: projectPath)
        } else if type == "mint" {
            return try UpMint(dictionary: dictionary, projectPath: projectPath)
        } else if type == "rome" {
            return try UpRome(dictionary: dictionary, projectPath: projectPath)
        }
        return nil
    }

    /// Returns true if the given tool is installed in the system.
    ///
    /// - Parameters
    ///   - name: Name of the tool.
    /// - Returns: True if homwebrew is installed in the system.
    func toolInstalled(_ name: String) -> Bool {
        (try? System.shared.which(name)) != nil
    }
}
