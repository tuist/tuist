import ProjectDescription

extension Platform {
    public var caseValue: String {
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
