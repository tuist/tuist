import Foundation
import TemplateDescription

enum PlatformError: Error, CustomStringConvertible {
    case parseFailed(String)
    
    var description: String {
        switch self {
        case let .parseFailed(value):
            return "\(value) is invalid. Platform should be either ios, tvos, or macos"
        }
    }
}

public enum Platform: String {
    case iOS = "ios"
    case macOS = "macos"
    case tvOS = "tvos"
    case watchOS = "watchos"
    
    public var caseValue: String {
        switch self {
        case .iOS: return "iOS"
        case .macOS: return "macOS"
        case .tvOS: return "tvOS"
        case .watchOS: return "watchOS"
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
