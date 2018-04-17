import Foundation

// MARK: - BuildConfiguration

enum BuildConfiguration: String {
    case debug
    case release
}

// MARK: - BuildConfiguration (Xcode)

extension BuildConfiguration: XcodeRepresentable {
    var xcodeValue: String {
        switch self {
        case .debug: return "Debug"
        case .release: return "Release"
        }
    }
}
