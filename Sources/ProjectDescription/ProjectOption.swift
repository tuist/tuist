import Foundation

/// Additional options related to the `Project`
public enum ProjectOption: Codable, Equatable {
    /// Text settings to override user ones for current project
    ///
    /// - Parameters:
    ///   - usesTabs: Use tabs over spaces.
    ///   - indentWidth: Indent width.
    ///   - tabWidth: Tab width.
    ///   - wrapsLines: Wrap lines.
    case textSettings(
        usesTabs: Bool? = nil,
        indentWidth: UInt? = nil,
        tabWidth: UInt? = nil,
        wrapsLines: Bool? = nil
    )
}

// MARK: - Options + Codable

extension ProjectOption {
    private enum OptionsCodingKeys: String, CodingKey {
        case textSettings
    }

    private enum TextSettingsKeys: String, CodingKey {
        case usesTabs
        case indentWidth
        case tabWidth
        case wrapsLines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: OptionsCodingKeys.self)

        if container.allKeys.contains(.textSettings), try container.decodeNil(forKey: .textSettings) == false {
            let textSettingsContainer = try container.nestedContainer(
                keyedBy: TextSettingsKeys.self,
                forKey: .textSettings
            )

            self = .textSettings(
                usesTabs: try textSettingsContainer.decodeIfPresent(Bool.self, forKey: .usesTabs),
                indentWidth: try textSettingsContainer.decodeIfPresent(UInt.self, forKey: .indentWidth),
                tabWidth: try textSettingsContainer.decodeIfPresent(UInt.self, forKey: .tabWidth),
                wrapsLines: try textSettingsContainer.decodeIfPresent(Bool.self, forKey: .wrapsLines)
            )
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown enum case"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: OptionsCodingKeys.self)

        switch self {
        case let .textSettings(usesTabs, indentWidth, tabWidth, wrapsLines):
            var associatedValues = container.nestedContainer(keyedBy: TextSettingsKeys.self, forKey: .textSettings)
            try associatedValues.encodeIfPresent(usesTabs, forKey: .usesTabs)
            try associatedValues.encodeIfPresent(indentWidth, forKey: .indentWidth)
            try associatedValues.encodeIfPresent(tabWidth, forKey: .tabWidth)
            try associatedValues.encodeIfPresent(wrapsLines, forKey: .wrapsLines)
        }
    }
}
