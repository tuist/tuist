import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// Up that bootstraps outdated Carthage dependencies.
class UpCarthage: Up, GraphInitiatable {
    /// The platforms Carthage dependencies should be bootstraped for.
    let platforms: [Platform]

    /// Indicates whether Carthage produces XCFrameworks or regular frameworks.
    let useXCFrameworks: Bool

    /// Indicates whether Carthage rebuilds the dependency from source instead of using downloaded binaries when possible.
    let noUseBinaries: Bool

    /// Up homebrew for installing Carthge.
    let upHomebrew: Upping

    /// Carthage instace to interact with the project Carthage setup.
    let carthage: Carthaging

    /// Initializes the Carthage command.
    ///
    /// - Parameters:
    ///   - platforms: The platforms Carthage dependencies should be bootstraped for.
    ///   - useXCFrameworks: Indicates whether Carthage produces XCFrameworks or regular frameworks.
    ///   - noUseBinaries: Indicates whether Carthage rebuilds the dependency from source instead of using downloaded binaries when possible.
    ///   - upHomebrew: Up homebrew for installing Carthage.
    ///   - carthage: Carthage instace to interact with the project Carthage setup.
    init(platforms: [Platform],
         useXCFrameworks: Bool,
         noUseBinaries: Bool,
         upHomebrew: Upping = UpHomebrew(packages: ["carthage"]),
         carthage: Carthaging = Carthage())
    {
        self.platforms = platforms
        self.useXCFrameworks = useXCFrameworks
        self.noUseBinaries = noUseBinaries
        self.upHomebrew = upHomebrew
        self.carthage = carthage
        super.init(name: "Carthage bootstrap")
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest. This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required convenience init(dictionary: JSON, projectPath _: AbsolutePath) throws {
        var platforms: [Platform] = []
        if let platformStrings: [String] = try? dictionary.get("platforms") {
            platforms = platformStrings.compactMap {
                Platform(rawValue: $0)
            }
        }
        let useXCFrameworks: Bool = try dictionary.get("useXCFrameworks")
        let noUseBinaries: Bool = try dictionary.get("noUseBinaries")
        self.init(platforms: platforms, useXCFrameworks: useXCFrameworks, noUseBinaries: noUseBinaries)
    }

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameters
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    override func isMet(projectPath: AbsolutePath) throws -> Bool {
        if try !upHomebrew.isMet(projectPath: projectPath) { return false }
        guard let outdated = try carthage.outdated(path: projectPath) else { return false }
        return outdated.isEmpty
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    override func meet(projectPath: AbsolutePath) throws {
        // Installing Carthage
        if try !upHomebrew.isMet(projectPath: projectPath) {
            try upHomebrew.meet(projectPath: projectPath)
        }

        /// Bootstrapping Carthage dependencies.
        let outdated = try carthage.outdated(path: projectPath) ?? []
        try carthage.bootstrap(
            path: projectPath,
            platforms: platforms,
            useXCFrameworks: useXCFrameworks,
            noUseBinaries: noUseBinaries,
            dependencies: outdated
        )
    }

    func whatever() {}
}
