import Foundation
import TSCBasic

public enum Package: Equatable {
    case remote(url: String, requirement: PackageRequirement)
    case local(path: AbsolutePath)
}
