import Basic
import Foundation
import TuistCore

/// Command that installs Homebrew and packages.
class UpHomebrewTap: Up, GraphInitiatable {
    /// Up name.
    static let name: String = "Homebrew tap"

    /// Tap repositories
    let repositories: [String]

    /// Up homebrew for installing Carthge.
    let upHomebrew: Upping

    /// Initializes the Homebrew tap up.
    ///
    /// - Parameter
    ///     - repositories: List of repositories to be tapped.
    ///   - upHomebrew: Up homebrew for installing Homebrew.
    init(repositories: [String],
         upHomebrew: Upping = UpHomebrew(packages: [])) {
        self.repositories = repositories
        self.upHomebrew = upHomebrew
        super.init(name: UpHomebrewTap.name)
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest.
    ///     This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    ///   - fileHandler: File handler for any file operations like checking whether a file exists or not.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required convenience init(dictionary: JSON, projectPath _: AbsolutePath, fileHandler _: FileHandling) throws {
        self.init(repositories: try dictionary.get("repositories"))
    }

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameters
    ///   - system: System instance to run commands on the shell.
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    override func isMet(system: Systeming, projectPath: AbsolutePath) throws -> Bool {
        guard try upHomebrew.isMet(system: system, projectPath: projectPath) else { return false }
        let taps = try self.taps(system: system)
        guard repositories.first(where: { !isTapConfigured($0, taps: taps) }) == nil else { return false }
        return true
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - system: System instance to run commands on the shell.
    ///   - printer: Printer instance to output information to the user.
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    override func meet(system: Systeming, printer: Printing, projectPath: AbsolutePath) throws {
        // Homebrew
        try upHomebrew.meet(system: system, printer: printer, projectPath: projectPath)

        // Taps
        let taps = try self.taps(system: system)
        let notConfigured = repositories.filter { !isTapConfigured($0, taps: taps) }
        for repository in notConfigured {
            printer.print("Adding repository tap: \(repository)")
            try system.run(["brew", "tap", repository])
        }
    }

    // MARK: - Fileprivate

    /// Returns true if a tap repository is configured in the system.
    ///
    /// - Parameters:
    ///   - repository: Tap repository.
    ///   - taps: The list of system taps.
    /// - Returns: True if the tap repository is configured in the system.
    fileprivate func isTapConfigured(_ repository: String, taps: [String]) -> Bool {
        return taps.first(where: { $0.contains(repository) }) != nil
    }

    /// Returns the list of taps that are available in the system.
    ///
    ///   - system: System instance to run commands on the shell.
    /// - Returns: The list of taps available in the system.
    /// - Throws: An error if the 'brew tap' command errors.
    fileprivate func taps(system: Systeming) throws -> [String] {
        return try system.capture(["brew", "tap"]).spm_chomp().split(separator: "\n").map(String.init)
    }
}
