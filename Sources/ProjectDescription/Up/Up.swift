import Foundation

/// It represents a command that configures the environment for the project to work.
/// The steps to set up the project are usually specified in the project README.
/// With Tuist, that's not necessary anymore because you can define declaratively those steps
/// and developers can run them by executing 'tuist up'
public class Up: Codable, Equatable {
    /// Returns an up that installs Homebrew packages.
    ///
    /// - Parameter packages: Packages to be installed.
    /// - Returns: Up instance to install Homebrew packages.
    public static func homebrew(packages: [String]) -> Up {
        UpHomebrew(packages: packages)
    }

    /// Returns an up that configures Homebrew tap repositories.
    ///
    /// - Parameter repositories: Repositories to be tapped.
    /// - Returns: Up to tap repositories in Homebrew.
    public static func homebrewTap(repositories: [String]) -> Up {
        UpHomebrewTap(repositories: repositories)
    }

    /// Returns an up that configures Homebrew cask projects.
    ///
    /// - Parameter projects: Projects to be installed with cask.
    /// - Returns: Up to cask projects in Homebrew.
    public static func homebrewCask(projects: [String]) -> Up {
        UpHomebrewCask(projects: projects)
    }

    /// Returns a user-defined up.
    ///
    /// - Parameters:
    ///   - name: Name of the command.
    ///   - meet: Shell command that needs to be executed if the command is not met in the environment.
    ///   - isMet: Shell command that should return a 0 exit status if the setup has already been done (e.g. which carthage)
    /// - Returns: User-defined up.
    public static func custom(name: String, meet: [String], isMet: [String]) -> Up {
        UpCustom(name: name, meet: meet, isMet: isMet)
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

    /// Returns an up that installs Mint packages specified in the Mintfile.
    ///
    /// - Parameters
    ///     - linkPackagesGlobally: A Boolean value indicating whether installing the packages of the Mintfile globally.
    /// - Returns: Up instance to install Mint packages.
    public static func mint(linkPackagesGlobally: Bool = false) -> Up {
        UpMint(linkPackagesGlobally: linkPackagesGlobally)
    }

    /// Returns an up that updates Carthage dependencies in the project directory using Rome.
    ///
    /// - Parameters
    ///     - platforms: The platforms Rome dependencies should be updated for. If the argument is not passed, the frameworks will be updated for all the platforms.
    ///     - cachePrefix: The cachePrefix that Rome should use when retrieving the cached dependencies
    /// - Returns: Up to pull dependencies from Carthage via Rome.
    public static func rome(platforms: [Platform]? = nil, cachePrefix: String? = nil) -> Up {
        let platforms = platforms ?? [.iOS, .macOS, .tvOS, .watchOS]
        return UpRome(platforms: platforms, cachePrefix: cachePrefix)
    }

    public static func == (lhs: Up, rhs: Up) -> Bool {
        lhs.equals(rhs)
    }

    func equals(_: Up) -> Bool {
        fatalError("Subclasses should override this method")
    }
}
