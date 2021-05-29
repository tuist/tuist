import Foundation

/// Custom up defined by the user.
class UpCustom: Up {
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
         isMet: [String])
    {
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

    override func equals(_ other: Up) -> Bool {
        guard let otherUpCustom = other as? UpCustom else { return false }
        return meet == otherUpCustom.meet &&
            isMet == otherUpCustom.isMet &&
            name == otherUpCustom.name
    }
}
