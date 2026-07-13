import Foundation
import Path

public enum Package: Equatable, Codable, Sendable {
    case remote(url: String, requirement: Requirement, traits: [String]? = nil)
    case local(path: AbsolutePath, traits: [String]? = nil)
}

extension XcodeGraph.Package {
    public var isRemote: Bool {
        switch self {
        case .remote:
            return true
        case .local:
            return false
        }
    }
}
