import Foundation

// MARK: - Platform

public enum Platform: String {
    case iOS
    case macOS
    case watchOS
    case tvOS
}

// MARK: - Platform (JSONConvertible)

extension Platform: JSONConvertible {
    func toJSON() -> JSON {
        return .string(rawValue)
    }
}
