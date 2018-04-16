import Foundation
import Unbox

// MARK: - BuildConfiguration

enum BuildConfiguration: String, UnboxableEnum {
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
