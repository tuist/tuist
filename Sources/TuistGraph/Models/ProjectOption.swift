import Foundation

/// Additional options related to the `Project`
public enum ProjectOption: Codable {
    /// Text settings to override user ones for current project
    case textSettings(TextSettings)

    /// Option name
    public var name: String {
        switch self {
        case .textSettings:
            return "textSettings"
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
        case (.textSettings, .textSettings):
            return true
        }
    }
}
