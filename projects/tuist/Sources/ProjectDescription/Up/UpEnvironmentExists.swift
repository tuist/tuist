import Foundation

/// Precondition required to succeed setup.
public class UpEnvironmentExists: UpRequired {
    /// Name of the command.
    let name: String

    /// Variable to examine.
    let variable: String

    /// Initializes a Precondition command.
    ///
    /// - Parameters:
    ///   - name: Name of the command.
    ///   - variable: Environment variable to be examined.
    init(name: String,
         variable: String)
    {
        self.name = name
        self.variable = variable
        super.init()
    }

    public enum CodingKeys: String, CodingKey {
        case name
        case variable
        case type
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        variable = try container.decode(String.self, forKey: .variable)
        try super.init(from: decoder)
    }

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(variable, forKey: .variable)
        try container.encode("variable_exists", forKey: .type)
    }

    override public func equals(_ other: UpRequired) -> Bool {
        guard let other = other as? UpEnvironmentExists else { return false }
        return name == other.name &&
            variable == other.variable
    }
}
