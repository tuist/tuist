import Foundation

/// Additional options related to the `Project`
public enum ProjectOption: Codable {
    /// Disables generating Bundle accessors.
    case disableBundleAccessors

    /// Disable the synthesized resource accessors generation
    case disableSynthesizedResourceAccessors

    /// Text settings to override user ones for current project
    case textSettings(TextSettings)

    /// Option name
    public var name: String {
        switch self {
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
    public var disableBundleAccessors: Bool {
        contains(.disableBundleAccessors)
    }

    public var disableSynthesizedResourceAccessors: Bool {
        contains(.disableSynthesizedResourceAccessors)
    }

    public var textSettings: TextSettings? {
        compactMap {
            switch $0 {
            case .disableBundleAccessors, .disableSynthesizedResourceAccessors:
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
        case (.disableBundleAccessors, .disableBundleAccessors),
             (.disableSynthesizedResourceAccessors, .disableSynthesizedResourceAccessors),
             (.textSettings, .textSettings):
            return true
        case (.disableBundleAccessors, _), (.disableSynthesizedResourceAccessors, _), (.textSettings, _):
            return false
        }
    }
}
