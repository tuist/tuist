import Foundation

/// Up that updates Carthage dependencies that need to be updated
class UpCarthage: Up {
    /// The platforms Carthage dependencies should be updated for.
    let platforms: [Platform]

    /// Initializes the Carthage up.
    ///
    /// - Parameter platforms: The platforms Carthage dependencies should be updated for.
    init(platforms: [Platform]) {
        self.platforms = platforms
        super.init()
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case platforms
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platforms = try container.decode([Platform].self, forKey: .platforms)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("carthage", forKey: .type)
        try container.encode(platforms, forKey: .platforms)
    }

    public static func == (lhs: UpCarthage, rhs: UpCarthage) -> Bool {
        return lhs.platforms == rhs.platforms
    }
}
