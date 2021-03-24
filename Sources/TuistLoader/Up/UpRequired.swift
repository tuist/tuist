import Foundation
import TSCBasic
import TuistSupport

class UpRequired: Upping {
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
    static func with(dictionary: JSON, projectPath: AbsolutePath) throws -> UpRequired? {
        let type: String = try dictionary.get("type")
        if type == "precondition" {
            return try UpPrecondition(dictionary: dictionary, projectPath: projectPath)
        }
        return nil
    }
}
