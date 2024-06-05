import Foundation
import TSCBasic

public enum Package: Equatable, Codable {
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
