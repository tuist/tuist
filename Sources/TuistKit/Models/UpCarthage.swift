import Basic
import Foundation
import TuistCore

/// Up that updates outdated Carthage dependencies.
class UpCarthage: Up, GraphInitiatable {
    /// The platforms Carthage dependencies should be updated for.
    let platforms: [Platform]

    /// Up homebrew for installing Carthge.
    let upHomebrew: Upping

    /// Initializes the Carthage command.
    ///
    /// - Parameters:
    ///   - platforms: The platforms Carthage dependencies should be updated for.
    ///   - upHomebrew: Up homebrew for installing Carthge.
    init(platforms: [Platform], upHomebrew: Upping = UpHomebrew(packages: ["carthage"])) {
        self.platforms = platforms
        self.upHomebrew = upHomebrew
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
    override func isMet(system: Systeming, projectPath: AbsolutePath) throws -> Bool {
        if try !upHomebrew.isMet(system: system, projectPath: projectPath) { return false }
        let carthagePath = try system.which("carthage")

        do {
            // TODO: Verify if "validate" is the right command here
            try system.capture(carthagePath,
                               arguments: ["validate"],
                               verbose: false,
                               workingDirectoryPath: projectPath,
                               environment: System.userEnvironment).throwIfError()
            return true
        } catch {
            return false
        }
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - system: System instance to run commands on the shell.
    ///   - printer: Printer instance to output information to the user.
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    override func meet(system: Systeming, printer: Printing, projectPath: AbsolutePath) throws {
        // Installing Carthage
        if try !upHomebrew.isMet(system: system, projectPath: projectPath) {
            try upHomebrew.meet(system: system, printer: printer, projectPath: projectPath)
        }

        /// Updating Carthage dependencies.
        let arguments = ["update", "--platform", platforms.map({ $0.caseValue }).joined(separator: ",")]
        printer.print("Updating Carthage dependencies")
        let carthagePath = try system.which("carthage")
        try system.popen(carthagePath,
                         arguments: arguments,
                         verbose: false,
                         workingDirectoryPath: projectPath,
                         environment: System.userEnvironment)
    }

    func whatever() {}
}
