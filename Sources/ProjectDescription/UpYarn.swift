import Foundation

/// Up that installs outdated NPM dependencies using Yarn.
class UpYarn: Up {
    public enum CodingKeys: String, CodingKey {
        case type
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("yarn", forKey: .type)
    }
}
