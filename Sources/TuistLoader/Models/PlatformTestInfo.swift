#if DEBUG
    import Foundation
    import ProjectDescription

    extension Platform {
        public func testVersion() -> String {
            switch self {
            case .iOS: return "11.0"
            case .macOS: return "10.15"
            case .watchOS: return "8.5"
            case .tvOS: return "11.0"
            case .visionOS: return "1.0"
            }
        }
    }

#endif
