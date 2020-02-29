public enum Platform: String {
    case iOS = "ios"
    case macOS = "macos"
    
    public var caseValue: String {
        switch self {
        case .iOS:
            return "iOS"
        case .macOS:
            return "macOS"
        }
    }
}
