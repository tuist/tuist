import Foundation

/// It represents a command that configures the environment for the project to work.
/// The steps to set up the project are usually specified in the project README.
/// With Tuist, that's not necessary anymore because you can define declaratively those steps
/// and developers can run them by executing 'tuist up'
public class Up: Codable {
    /// Returns an up that installs Homebrew packages.
    ///
    /// - Parameter packages: Packages to be installed.
    /// - Returns: Up instance to install Homebrew packages.
    public static func homebrew(packages: [String]) -> Up {
        return UpHomebrew(packages: packages)
    }

    /// Returns an up that configures Homebrew tap repositories.
    ///
    /// - Parameter repositories: Repositories to be tapped.
    /// - Returns: Up to tap repositories in Homebrew.
    public static func homebrewTap(repositories: [String]) -> Up {
        return UpHomebrewTap(repositories: repositories)
    }

    /// Returns a user-defined up.
    ///
    /// - Parameters:
    ///   - name: Name of the command.
    ///   - meet: Shell command that needs to be executed if the command is not met in the environment.
    ///   - isMet: Shell command that should return a 0 exit status if the setup has already been done (e.g. which carthage)
    /// - Returns: User-defined up.
    public static func custom(name: String, meet: [String], isMet: [String]) -> Up {
        return UpCustom(name: name, meet: meet, isMet: isMet)
    }

    /// Returns an up that updates Carthage dependencies in the project directory.
    ///
    /// - Parameters
    ///     - platforms: The platforms Carthage dependencies should be updated for. If the argument is not passed, the frameworks will be updated for all the platforms.
    /// - Returns: Up to pull Carthage dependencies.
    public static func carthage(platforms: [Platform]? = nil) -> Up {
        let platforms = platforms ?? [.iOS, .macOS, .tvOS, .watchOS]
        return UpCarthage(platforms: platforms)
    }
}
