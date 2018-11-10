import Basic
import Foundation
import TuistCore

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
