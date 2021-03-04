import Foundation
import TSCBasic
import TuistSupport

/// Command that installs Homebrew and packages.
class UpHomebrew: Up, GraphInitiatable {
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
    ///   - projectPath: Absolute path to the folder that contains the manifest.
    ///     This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required init(dictionary: JSON, projectPath _: AbsolutePath) throws {
        packages = try dictionary.get("packages")
        super.init(name: "Homebrew")
    }

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameters
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    override func isMet(projectPath _: AbsolutePath) throws -> Bool {
        let packagesInstalled = packages.allSatisfy { packageInstalled($0) }
        return toolInstalled("brew") && packagesInstalled
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    override func meet(projectPath _: AbsolutePath) throws {
        if !toolInstalled("brew") {
            logger.notice("Installing Homebrew")
            try System.shared.runAndPrint(
                "/usr/bin/ruby",
                "-e",
                "\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)\"",
                verbose: true,
                environment: System.shared.env
            )
        }
        let nonInstalledPackages = packages.filter { !packageInstalled($0) }
        try nonInstalledPackages.forEach { package in
            logger.notice("Installing Homebrew package: \(package)")
            try System.shared.runAndPrint(
                "/usr/local/bin/brew",
                "install",
                package,
                verbose: true,
                environment: System.shared.env
            )
        }
    }

    private func packageInstalled(_ name: String) -> Bool {
        (try? System.shared.run("/usr/local/bin/brew", "list", name)) != nil
    }
}
