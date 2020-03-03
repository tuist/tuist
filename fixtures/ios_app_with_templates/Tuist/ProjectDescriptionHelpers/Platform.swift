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
