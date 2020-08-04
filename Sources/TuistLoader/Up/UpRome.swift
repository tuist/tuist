import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// Up that updates outdated Rome dependencies.
class UpRome: Up, GraphInitiatable {
    /// The platforms Rome dependencies should be updated for.
    let platforms: [Platform]

    /// The cache prefix to use when downloading dependencies
    let cachePrefix: String?

    /// Up homebrew for installing Rome.
    let upHomebrew: Upping

    /// Rome instace to interact with the project Romefile setup.
    let rome: Romeaging

    /// Initializes the Carthage command.
    ///
    /// - Parameters:
    ///   - platforms:      The platforms Carthage dependencies should be updated for.
    ///   - cachePrefix:    The cachePrefix used when downloading Rome dependencies.
    ///   - upHomebrew:     Up homebrew for installing Carthage.
    ///   - rome:           Rome instace to interact with the projects Rome setup.
    init(platforms: [Platform],
         cachePrefix: String?,
         upHomebrew: Upping = UpHomebrewTap(repositories: ["tmspzz/tap"]),
         rome: Romeaging = Rome())
    {
        self.platforms = platforms
        self.cachePrefix = cachePrefix
        self.upHomebrew = upHomebrew
        self.rome = rome
        super.init(name: "Rome download")
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest. This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required convenience init(dictionary: JSON, projectPath _: AbsolutePath) throws {
        var platforms: [Platform] = []
        var cachePrefix: String?
        if let platformStrings: [String] = try? dictionary.get("platforms") {
            platforms = platformStrings.compactMap {
                Platform(rawValue: $0)
            }
        }

        if let cachePrefixString: String = dictionary.get("cachePrefix") {
            cachePrefix = cachePrefixString
        }
        self.init(platforms: platforms, cachePrefix: cachePrefix)
    }

    /// Returns true when the command doesn't need to be run.
    ///
    /// - Parameters
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    override func isMet(projectPath: AbsolutePath) throws -> Bool {
        if try !upHomebrew.isMet(projectPath: projectPath) { return false }
        guard let missing = try rome.missing(platforms: platforms, cachePrefix: cachePrefix) else { return false }
        return missing.isEmpty
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: An error if any error is thrown while running it.
    override func meet(projectPath: AbsolutePath) throws {
        /// Installing Rome
        if try !upHomebrew.isMet(projectPath: projectPath) {
            try upHomebrew.meet(projectPath: projectPath)
        }

        /// Downloading Rome dependencies.
        try rome.download(platforms: platforms, cachePrefix: cachePrefix)
    }
}
