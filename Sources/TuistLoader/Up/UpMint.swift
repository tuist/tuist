import Foundation
import TSCBasic
import TuistSupport

public enum UpMintError: FatalError, Equatable {
    case mintfileNotFound(AbsolutePath)

    public var description: String {
        switch self {
        case let .mintfileNotFound(path):
            return "Mintfile not found at path \(path.pathString)"
        }
    }

    public var type: ErrorType {
        switch self {
        case .mintfileNotFound:
            return .abort
        }
    }
}

/// Command that installs Mint and packages.
class UpMint: Up, GraphInitiatable {
    /// A Boolean value indicating whether installing the packages of the Mintfile globally.
    let linkPackagesGlobally: Bool

    /// Up homebrew for installing Mint.
    let upHomebrew: Upping

    init(linkPackagesGlobally: Bool, upHomebrew: Upping = UpHomebrew(packages: ["mint"])) {
        self.linkPackagesGlobally = linkPackagesGlobally
        self.upHomebrew = upHomebrew
        super.init(name: "Mint")
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest.
    ///     This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required convenience init(dictionary: JSON, projectPath _: AbsolutePath) throws {
        let linkPackagesGlobally: Bool = try dictionary.get("linkPackagesGlobally")
        self.init(linkPackagesGlobally: linkPackagesGlobally)
    }

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameters
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    override func isMet(projectPath: AbsolutePath) throws -> Bool {
        if try !upHomebrew.isMet(projectPath: projectPath) {
            return false
        }

        let mintfile = projectPath.appending(component: "Mintfile")
        if !FileHandler.shared.exists(mintfile) {
            throw UpMintError.mintfileNotFound(projectPath)
        }

        let output = try FileHandler.shared.readTextFile(mintfile)
        let packages = output.split(separator: "\n")
        for package in packages {
            if (try? System.shared.capture(["mint", "which", "\(package)"])) == nil {
                return false
            }
        }

        return true
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    override func meet(projectPath: AbsolutePath) throws {
        // Installing Mint
        if try !upHomebrew.isMet(projectPath: projectPath) {
            try upHomebrew.meet(projectPath: projectPath)
        }

        let mintfile = projectPath.appending(component: "Mintfile")
        if !FileHandler.shared.exists(mintfile) {
            throw UpMintError.mintfileNotFound(projectPath)
        }

        var command = ["mint", "bootstrap", "-m", "\(mintfile.pathString)"]
        if linkPackagesGlobally { command.append("--link") }
        try System.shared.runAndPrint(command, verbose: true, environment: System.shared.env)
    }
}
