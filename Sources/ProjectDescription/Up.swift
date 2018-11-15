import Foundation

/// It represents a command that configures the environment for the project to work.
/// The steps to set up the project are usually specified in the project README.
/// With Tuist, that's not necessary anymore because you can define declaratively those steps
/// and developers can run them by executing 'tuist up'
public class Up: Codable {
    /// Returns a command that installs Homebrew packages.
    ///
    /// - Parameter packages: Packages to be installed.
    /// - Returns: The Homebrew setup command.
    public static func homebrew(packages: [String]) -> Up {
        return UpHomebrew(packages: packages)
    }

    /// It return a user-defined command.
    ///
    /// - Parameters:
    ///   - name: Name of the command.
    ///   - meet: Shell command that needs to be executed if the command is not met in the environment.
    ///   - isMet: Shell command that should return a 0 exit status if the setup has already been done (e.g. which carthage)
    /// - Returns: The custom command.
    public static func custom(name: String, meet: [String], isMet: [String]) -> Up {
        return UpCustom(name: name, meet: meet, isMet: isMet)
    }
}
