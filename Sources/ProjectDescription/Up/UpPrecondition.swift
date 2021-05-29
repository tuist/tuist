import Foundation

/// Precondition required to succeed setup.
class UpPrecondition: UpRequired {
    /// Name of the command.
    let name: String

    /// Advice to give the user if the condition isn’t met.
    let advice: String

    /// Shell command that should return a 0 exit status if the condition is met.
    let isMet: [String]

    /// Initializes a Precondition command.
    ///
    /// - Parameters:
    ///   - name: Name of the command.
    ///   - advice: Output shown to the user if this condition is not met.
    ///   - isMet: Shell command that should return a 0 exit status if the setup has already been done.
    init(name: String,
         advice: String,
         isMet: [String])
    {
        self.name = name
        self.advice = advice
        self.isMet = isMet
        super.init()
    }

    public enum CodingKeys: String, CodingKey {
        case name
        case advice
        case isMet = "is_met"
        case type
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        advice = try container.decode(String.self, forKey: .advice)
        isMet = try container.decode([String].self, forKey: .isMet)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(advice, forKey: .advice)
        try container.encode(isMet, forKey: .isMet)
        try container.encode("precondition", forKey: .type)
    }

    override func equals(_ other: UpRequired) -> Bool {
        guard let other = other as? UpPrecondition else { return false }
        return advice == other.advice &&
            isMet == other.isMet &&
            name == other.name
    }
}
