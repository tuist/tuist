import Foundation

/// Additional options related to the `Project`
public enum ProjectOption: Codable {
    /// Text settings to override user ones for current project
    case textSettings(TextSettings)

    /// Disable the synthesized resource accessors generation
    case disableSynthesizedResourceAccessors

    /// Option name
    public var name: String {
        switch self {
        case .textSettings:
            return "textSettings"
        case .disableSynthesizedResourceAccessors:
            return "disableSynthesizedResourceAccessors"
        }
    }
}

// MARK: - Array + ProjectOption

extension Array where Element == ProjectOption {
    public var textSettings: TextSettings? {
        compactMap {
            switch $0 {
            case let .textSettings(textSettings):
                return textSettings
            case .disableSynthesizedResourceAccessors:
                return nil
            }
        }.first
    }

    public var disableSynthesizedResourceAccessors: Bool {
        contains(.disableSynthesizedResourceAccessors)
    }
}

// MARK: - Options + Hashable

extension ProjectOption: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    public static func == (lhs: ProjectOption, rhs: ProjectOption) -> Bool {
        switch (lhs, rhs) {
        case (.textSettings, .textSettings), (.disableSynthesizedResourceAccessors, .disableSynthesizedResourceAccessors):
            return true
        case (.textSettings, .disableSynthesizedResourceAccessors), (.disableSynthesizedResourceAccessors, .textSettings):
            return false
        }
    }
}

// MARK: - Options + Codable

extension ProjectOption {
    internal enum CodingKeys: String, CodingKey {
        case textSettings
        case disableSynthesizedResourceAccessors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.disableSynthesizedResourceAccessors) {
            self = .disableSynthesizedResourceAccessors
        } else if container.allKeys.contains(.textSettings), try container.decodeNil(forKey: .textSettings) == false {
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
        case .disableSynthesizedResourceAccessors:
            try container.encode(true, forKey: .disableSynthesizedResourceAccessors)
        }
    }
}
