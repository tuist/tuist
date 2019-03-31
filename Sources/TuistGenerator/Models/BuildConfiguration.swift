import Foundation

public enum BuildConfiguration: String {
    case debug
    case release
}

extension BuildConfiguration: XcodeRepresentable {
    var xcodeValue: String {
        switch self {
        case .debug: return "Debug"
        case .release: return "Release"
        }
    }
}
