import Foundation
import Path

public enum Package: Equatable, Codable, Sendable {
    case remote(url: String, requirement: Requirement)
    case local(path: AbsolutePath)
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
