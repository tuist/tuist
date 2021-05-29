import Foundation

/// Up that configures a Homebrew tap in the system.
class UpHomebrewTap: Up {
    /// Repositories to be tapped.
    let repositories: [String]

    /// Initializes the up Homebrew tap with its attributes.
    ///
    /// - Parameter repositories: Repositories to be tapped.
    init(repositories: [String]) {
        self.repositories = repositories
        super.init()
    }

    public enum CodingKeys: String, CodingKey {
        case repositories
        case type
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repositories = try container.decode([String].self, forKey: .repositories)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(repositories, forKey: .repositories)
        try container.encode("homebrew-tap", forKey: .type)
    }

    override func equals(_ other: Up) -> Bool {
        guard let otherUpHomebrewTap = other as? UpHomebrewTap else { return false }
        return repositories == otherUpHomebrewTap.repositories
    }
}
