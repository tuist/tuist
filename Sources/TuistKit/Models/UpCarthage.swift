import Basic
import Foundation
import TuistCore

/// Up that updates outdated Carthage dependencies.
class UpCarthage: Up, GraphInitiatable {
    /// The platforms Carthage dependencies should be updated for.
    let platforms: [Platform]

    /// Initializes the Carthage command.
    ///
    /// - Parameter platforms: The platforms Carthage dependencies should be updated for.
    init(platforms: [Platform]) {
        self.platforms = platforms
        super.init(name: "Carthage update")
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest. This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    ///   - fileHandler: File handler for any file operations like checking whether a file exists or not.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required convenience init(dictionary: JSON, projectPath _: AbsolutePath, fileHandler _: FileHandling) throws {
        var platforms: [Platform] = []
        if let platformStrings: [String] = try? dictionary.get("platforms") {
            platforms = platformStrings.compactMap({
                Platform(rawValue: $0)
            })
        }
        self.init(platforms: platforms)
    }

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameters
    ///   - system: System instance to run commands on the shell.
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    override func isMet(system: Systeming, projectPath _: AbsolutePath) throws -> Bool {
        // TODO:
        return false
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - system: System instance to run commands on the shell.
    ///   - printer: Printer instance to output information to the user.
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    override func meet(system: Systeming, printer: Printing, projectPath _: AbsolutePath) throws {}
}
