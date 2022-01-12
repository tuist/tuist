import Foundation

/// Additional options related to the `Project`
public enum ProjectOption: Codable {
    /// Defines how to group targets in automatically generated schemes
    case automaticSchemesGrouping(AutomaticSchemesGrouping)

    /// Disables generating Bundle accessors.
    case disableBundleAccessors

    /// Disable the synthesized resource accessors generation
    case disableSynthesizedResourceAccessors

    /// Text settings to override user ones for current project
    case textSettings(TextSettings)

    /// Option name
    public var name: String {
        switch self {
        case .automaticSchemesGrouping:
            return "automaticSchemesGrouping"
        case .disableBundleAccessors:
            return "disableBundleAccessors"
        case .disableSynthesizedResourceAccessors:
            return "disableSynthesizedResourceAccessors"
        case .textSettings:
            return "textSettings"
        }
    }
}

// MARK: - Array + ProjectOption

extension Array where Element == ProjectOption {
    public var automaticSchemesGrouping: AutomaticSchemesGrouping {
        compactMap {
            switch $0 {
            case let .automaticSchemesGrouping(grouping):
                return grouping
            case .disableBundleAccessors, .disableSynthesizedResourceAccessors, .textSettings:
                return nil
            }
        }.first ?? .byName(
            build: ["Implementation", "Interface", "Mocks", "Testing"],
            test: ["Tests", "UITests"],
            run: ["App", "Demo"]
        )
    }

    public var disableBundleAccessors: Bool {
        contains(.disableBundleAccessors)
    }

    public var disableSynthesizedResourceAccessors: Bool {
        contains(.disableSynthesizedResourceAccessors)
    }

    public var textSettings: TextSettings? {
        compactMap {
            switch $0 {
            case .automaticSchemesGrouping, .disableBundleAccessors, .disableSynthesizedResourceAccessors:
                return nil
            case let .textSettings(textSettings):
                return textSettings
            }
        }.first
    }
}

// MARK: - Options + Hashable

extension ProjectOption: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    public static func == (lhs: ProjectOption, rhs: ProjectOption) -> Bool {
        switch (lhs, rhs) {
        case (.automaticSchemesGrouping, .automaticSchemesGrouping),
             (.disableBundleAccessors, .disableBundleAccessors),
             (.disableSynthesizedResourceAccessors, .disableSynthesizedResourceAccessors),
             (.textSettings, .textSettings):
            return true
        case (.automaticSchemesGrouping, _), (.disableBundleAccessors, _), (.disableSynthesizedResourceAccessors, _),
             (.textSettings, _):
            return false
        }
    }
}

// MARK: - Options + Codable

extension ProjectOption {
    internal enum CodingKeys: String, CodingKey {
        case automaticSchemesGrouping
        case disableBundleAccessors
        case disableSynthesizedResourceAccessors
        case textSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.allKeys.contains(.automaticSchemesGrouping),
           try container.decodeNil(forKey: .automaticSchemesGrouping) == false
        {
            var associatedValues = try container.nestedUnkeyedContainer(forKey: .automaticSchemesGrouping)
            let automaticSchemesGrouping = try associatedValues.decode(AutomaticSchemesGrouping.self)
            self = .automaticSchemesGrouping(automaticSchemesGrouping)
        } else if container.contains(.disableBundleAccessors) {
            self = .disableBundleAccessors
        } else if container.contains(.disableSynthesizedResourceAccessors) {
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
        case let .automaticSchemesGrouping(grouping):
            var associatedValues = container.nestedUnkeyedContainer(forKey: .automaticSchemesGrouping)
            try associatedValues.encode(grouping)
        case .disableBundleAccessors:
            try container.encode(true, forKey: .disableBundleAccessors)
        case .disableSynthesizedResourceAccessors:
            try container.encode(true, forKey: .disableSynthesizedResourceAccessors)
        case let .textSettings(textSettings):
            var associatedValues = container.nestedUnkeyedContainer(forKey: .textSettings)
            try associatedValues.encode(textSettings)
        }
    }
}
