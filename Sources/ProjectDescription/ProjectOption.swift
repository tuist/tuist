import Foundation

/// Additional options related to the `Project`
public enum ProjectOption: Codable, Equatable {
    /// Text settings to override user ones for current project
    case textSettings(TextSettings)
}

// MARK: - Options + Codable

extension ProjectOption {
    enum CodingKeys: String, CodingKey {
        case textSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.allKeys.contains(.textSettings), try container.decodeNil(forKey: .textSettings) == false {
            var associatedValues = try container.nestedUnkeyedContainer(forKey: .textSettings)
            let textSettings = try associatedValues.decode(TextSettings.self)
            self = .textSettings(textSettings)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown enum case"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .textSettings(textSettings):
            var associatedValues = container.nestedUnkeyedContainer(forKey: .textSettings)
            try associatedValues.encode(textSettings)
        }
    }
}
