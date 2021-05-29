import Foundation

/// A preset build configuration used for convenience
public enum PresetBuildConfiguration: String, Codable {
    case debug
    case release

    var name: String {
        switch self {
        case .debug: return "Debug"
        case .release: return "Release"
        }
    }
}
