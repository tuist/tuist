import Foundation
import TSCBasic

public enum Package: Equatable {
    case remote(url: String, requirement: Requirement)
    case local(path: AbsolutePath)
}
