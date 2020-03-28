import Foundation

/// Up that installs Homebrew and packages.
class UpHomebrew: Up {
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

    override func equals(_ other: Up) -> Bool {
        guard let otherUpHomebrew = other as? UpHomebrew else { return false }
        return packages == otherUpHomebrew.packages
    }
}
