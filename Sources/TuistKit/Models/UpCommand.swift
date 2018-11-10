import Basic
import Foundation
import TuistCore

/// It represents a command that configures the environment for the project to work.
/// The steps to set up the project are usually specified in the project README.
/// With Tuist, that's not necessary anymore because you can define declaratively those steps
/// and developers can run them by executing 'tuist up'
class UpCommand {
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
        super.init()
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
    }
}

/// Custom setup command defined by the user.
class CustomCommand: UpCommand, GraphInitiatable {
    /// Name of the command.
    let name: String

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
        self.name = name
        self.meet = meet
        self.isMet = isMet
        super.init()
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest. This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    ///   - fileHandler: File handler for any file operations like checking whether a file exists or not.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required init(dictionary: JSON, projectPath _: AbsolutePath, fileHandler _: FileHandling) throws {
        name = try dictionary.get("name")
        isMet = try dictionary.get("is_met")
        meet = try dictionary.get("meet")
    }
}
