import Basic
import Foundation
import XcodeProj

public enum SDKStatus {
    case required
    case optional
}

public enum Dependency: Equatable {
    case target(name: String)
    case project(target: String, path: RelativePath)
    case framework(path: RelativePath)
    case library(path: RelativePath, publicHeaders: RelativePath, swiftModuleMap: RelativePath?)
    case package(product: String)
    case sdk(name: String, status: SDKStatus)
    case cocoapods(path: RelativePath)
}

public enum Package: Equatable {
    case remote(url: String, requirement: Requirement)
    case local(path: AbsolutePath)
}

extension Package {
    public enum Requirement: Equatable {
        case upToNextMajor(String)
        case upToNextMinor(String)
        case range(from: String, to: String)
        case exact(String)
        case branch(String)
        case revision(String)

        var xcodeprojValue: XCRemoteSwiftPackageReference.VersionRequirement {
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
}
