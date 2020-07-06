import Foundation

/// Up that updates Rome dependencies that need to be updated
class UpRome: Up {
    /// The platforms Rome dependencies should be updated for.
    let platforms: [Platform]

    /// The prefix Rome should use when retrieving depdencies.
    let cachePrefix: String?

    /// Initializes the Rome up.
    ///
    /// - Parameter platforms:   The platforms Rome dependencies should be updated for.
    /// - Parameter cachePrefix: The cachePrefix Rome should use to retrieve dependencies.
    init(platforms: [Platform], cachePrefix: String? = nil) {
        self.platforms = platforms
        self.cachePrefix = cachePrefix
        super.init()
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case platforms
        case cachePrefix
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platforms = try container.decode([Platform].self, forKey: .platforms)
        cachePrefix = try container.decode(String.self, forKey: .cachePrefix)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("rome", forKey: .type)
        try container.encode(platforms, forKey: .platforms)
        try container.encode(cachePrefix, forKey: .cachePrefix)
    }

    override func equals(_ other: Up) -> Bool {
        guard let otherUpRome = other as? UpRome else { return false }
        return platforms == otherUpRome.platforms && cachePrefix == otherUpRome.cachePrefix
    }
}
