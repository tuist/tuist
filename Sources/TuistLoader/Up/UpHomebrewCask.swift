import Foundation
import TSCBasic
import TuistSupport

/// Command that installs Homebrew and packages.
class UpHomebrewCask: Up, GraphInitiatable {
    /// Up name.
    static let name: String = "Homebrew cask"

    /// Cask projects
    let projects: [String]

    /// Up homebrew for installing Carthge.
    let upHomebrew: Upping

    /// Initializes the Homebrew cask up.
    ///
    /// - Parameters:
    ///   - projects: List of projects to be installed with cask.
    ///   - upHomebrew: Up homebrew for installing Homebrew.
    init(projects: [String],
         upHomebrew: Upping = UpHomebrew(packages: [])) {
        self.projects = projects
        self.upHomebrew = upHomebrew
        super.init(name: UpHomebrewCask.name)
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest.
    ///     This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required convenience init(dictionary: JSON, projectPath _: AbsolutePath) throws {
        self.init(projects: try dictionary.get("projects"))
    }

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameters
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    override func isMet(projectPath: AbsolutePath) throws -> Bool {
        guard try upHomebrew.isMet(projectPath: projectPath) else { return false }
        let casks = try self.casks()
        guard projects.first(where: { !iscaskConfigured($0, casks: casks) }) == nil else { return false }
        return true
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    override func meet(projectPath: AbsolutePath) throws {
        // Homebrew
        try upHomebrew.meet(projectPath: projectPath)

        // casks
        let casks = try self.casks()
        let notConfigured = projects.filter { !iscaskConfigured($0, casks: casks) }
        for repository in notConfigured {
            logger.notice("Adding repository cask: \(repository)")
            try System.shared.run(["brew", "cask", repository])
        }
    }

    // MARK: - Fileprivate

    /// Returns true if a cask repository is configured in the system.
    ///
    /// - Parameters:
    ///   - repository: cask repository.
    ///   - casks: The list of system casks.
    /// - Returns: True if the cask repository is configured in the system.
    private func iscaskConfigured(_ repository: String, casks: [String]) -> Bool {
        casks.first(where: { $0.contains(repository) }) != nil
    }

    /// Returns the list of casks that are available in the system.
    ///
    /// - Returns: The list of casks available in the system.
    /// - Throws: An error if the 'brew cask' command errors.
    private func casks() throws -> [String] {
        try System.shared.capture(["brew", "cask"]).spm_chomp().split(separator: "\n").map(String.init)
    }
}
