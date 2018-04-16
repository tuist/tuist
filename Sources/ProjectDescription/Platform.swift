import Foundation

// MARK: - Platform

public enum Platform: String {
    case ios
    case macos
    case watchos
    case tvos
}

// MARK: - Platform (JSONConvertible)

extension Platform: JSONConvertible {
    func toJSON() -> JSON {
        return .string(rawValue)
    }
}
