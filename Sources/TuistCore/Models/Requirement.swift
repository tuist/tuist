import Foundation
import XcodeProj

public typealias Requirement = TuistCore.Requirement

public enum Requirement: Equatable {
    case upToNextMajor(String)
    case upToNextMinor(String)
    case range(from: String, to: String)
    case exact(String)
    case branch(String)
    case revision(String)

    public var xcodeprojValue: XCRemoteSwiftPackageReference.VersionRequirement {
        switch self {
        case let .branch(branch):
            return .branch(branch)
        case let .exact(version):
            return .exact(version)
        case let .range(from, to):
            return .range(from: from, to: to)
        case let .revision(revision):
            return .revision(revision)
        case let .upToNextMinor(version):
            return .upToNextMinorVersion(version)
        case let .upToNextMajor(version):
            return .upToNextMajorVersion(version)
        }
    }
}
