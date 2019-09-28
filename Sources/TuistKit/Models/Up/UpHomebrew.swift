import Basic
import Foundation
import TuistCore

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
    ///   - system: System instance to run commands on the shell.
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    override func isMet(system: Systeming, projectPath _: AbsolutePath) throws -> Bool {
        let packagesInstalled = packages.allSatisfy { toolInstalled($0, system: system) }
        return toolInstalled("brew", system: system) && packagesInstalled
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - system: System instance to run commands on the shell.
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    override func meet(system: Systeming, projectPath _: AbsolutePath) throws {
        if !toolInstalled("brew", system: system) {
            Printer.shared.print("Installing Homebrew")
            try system.runAndPrint("/usr/bin/ruby", "-e", "\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)\"",
                                   verbose: true,
                                   environment: system.env)
        }
        let nonInstalledPackages = packages.filter { !toolInstalled($0, system: system) }
        try nonInstalledPackages.forEach { package in
            Printer.shared.print("Installing Homebrew package: \(package)")
            try system.runAndPrint("/usr/local/bin/brew", "install", package,
                                   verbose: true,
                                   environment: system.env)
        }
    }
}
