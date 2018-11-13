import Foundation

/// It represents a command that configures the environment for the project to work.
/// The steps to set up the project are usually specified in the project README.
/// With Tuist, that's not necessary anymore because you can define declaratively those steps
/// and developers can run them by executing 'tuist up'
public class UpCommand: Codable {
    /// Returns a command that installs Homebrew packages.
    ///
    /// - Parameter packages: Packages to be installed.
    /// - Returns: The Homebrew setup command.
    public static func homebrew(packages: [String]) -> UpCommand {
        return HomebrewCommand(packages: packages)
    }

    /// It return a user-defined command.
    ///
    /// - Parameters:
    ///   - name: Name of the command.
    ///   - meet: Shell command that needs to be executed if the command is not met in the environment.
    ///   - isMet: Shell command that should return a 0 exit status if the setup has already been done (e.g. which carthage)
    /// - Returns: The custom command.
    public static func custom(name: String, meet: [String], isMet: [String]) -> UpCommand {
        return CustomCommand(name: name, meet: meet, isMet: isMet)
    }
}

/// Command that installs Homebrew and packages.
fileprivate class HomebrewCommand: UpCommand {
    /// Homebrew packages to be installed.
    let packages: [String]

    /// Initializes the Homebrew command.
    ///
    /// - Parameter packages: Packages to be installed.
    init(packages: [String]) {
        self.packages = packages
        super.init()
    }

    public enum CodingKeys: String, CodingKey {
        case packages
        case type
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packages = try container.decode([String].self, forKey: .packages)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packages, forKey: .packages)
        try container.encode("homebrew", forKey: .type)
    }
}

/// Custom setup command defined by the user.
fileprivate class CustomCommand: UpCommand {
    /// Name of the command.
    let name: String

    /// Shell command that needs to be executed if the command is not met in the environment.
    let meet: [String]

    /// Shell command that should return a 0 exit status if the setup has already been done (e.g. which carthage).
    let isMet: [String]

    /// Initializes a custom command.
    ///
    /// - Parameters:
    ///   - name: Name of the command.
    ///   - meet: Shell command that needs to be executed if the command is not met in the environment.
    ///   - isMet: Shell command that should return a 0 exit status if the setup has already been done (e.g. which carthage).
    init(name: String,
         meet: [String],
         isMet: [String]) {
        self.name = name
        self.meet = meet
        self.isMet = isMet
        super.init()
    }

    public enum CodingKeys: String, CodingKey {
        case name
        case meet
        case isMet = "is_met"
        case type
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        meet = try container.decode([String].self, forKey: .meet)
        isMet = try container.decode([String].self, forKey: .isMet)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(isMet, forKey: .isMet)
        try container.encode(meet, forKey: .meet)
        try container.encode("custom", forKey: .type)
    }
}
