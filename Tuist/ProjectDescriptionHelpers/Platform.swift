import Foundation
import ProjectDescription

enum PlatformError: Error, CustomStringConvertible {
    case parseFailed(String)

    var description: String {
        switch self {
        case let .parseFailed(value):
            return "\(value) is invalid. Platform should be either ios, tvos, or macos"
        }
    }
}

import ProjectDescription

public extension Platform {
    var caseValue: String {
        switch self {
        case .iOS:
            return "iOS"
        case .macOS:
            return "macOS"
        case .watchOS:
            return "watchOS"
        case .tvOS:
            return "tvOS"
        }
    }
}

public extension Platform {
    static func getFromAttributes() throws -> Platform {
        let attributeValue = try getAttribute(for: "platform")
        guard let platform = Platform(rawValue: attributeValue) else { throw PlatformError.parseFailed(attributeValue) }
        return platform
    }
}
