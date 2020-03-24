import Foundation

/// Up that installs Mint and packages.
class UpMint: Up {
    /// A Boolean value indicating whether installing the packages of the Mintfile globally.
    let linkPackagesGlobally: Bool

    /// Initializes the Mint up.
    ///
    /// - Parameter linkPackagesGlobally: A Boolean value indicating whether installing the packages of the Mintfile globally.
    init(linkPackagesGlobally: Bool) {
        self.linkPackagesGlobally = linkPackagesGlobally
        super.init()
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case linkPackagesGlobally
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        linkPackagesGlobally = try container.decode(Bool.self, forKey: .linkPackagesGlobally)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("mint", forKey: .type)
        try container.encode(linkPackagesGlobally, forKey: .linkPackagesGlobally)
    }

    override func equals(_ other: Up) -> Bool {
        guard let otherUpMint = other as? UpMint else { return false }
        return linkPackagesGlobally == otherUpMint.linkPackagesGlobally
    }
}
