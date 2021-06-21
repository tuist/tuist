import Foundation
import TuistGraph
import XcodeProj

extension Requirement {
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
