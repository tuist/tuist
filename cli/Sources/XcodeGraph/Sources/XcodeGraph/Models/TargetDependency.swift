import Foundation
import Path

public enum LinkingStatus: String, Hashable, Codable, Sendable {
    case required
    case optional
    case none
}

public enum XCFrameworkSignature: Equatable, Hashable, Codable, Sendable {
    case unsigned
    case signedWithAppleCertificate(teamIdentifier: String, teamName: String)
    case selfSigned(fingerprint: String)

    public func signatureString() -> String? {
        switch self {
        case .unsigned:
            return nil
        case let .selfSigned(fingerprint: fingerprint):
            return "SelfSigned:\(fingerprint)"
        case let .signedWithAppleCertificate(teamIdentifier: teamIdentifier, teamName: teamName):
            return "AppleDeveloperProgram:\(teamIdentifier):\(teamName)"
        }
    }
}

public enum TargetDependency: Equatable, Hashable, Codable, Sendable {
    public enum PackageType: String, Equatable, Hashable, Codable, Sendable {
        case runtime
        case runtimeEmbedded
        case plugin
        case macro
    }

    case target(name: String, status: LinkingStatus = .required, condition: PlatformCondition? = nil)
    case project(target: String, path: AbsolutePath, status: LinkingStatus = .required, condition: PlatformCondition? = nil)
    case framework(path: AbsolutePath, status: LinkingStatus, condition: PlatformCondition? = nil)
    case xcframework(
        path: AbsolutePath,
        expectedSignature: XCFrameworkSignature?,
        status: LinkingStatus,
        condition: PlatformCondition? = nil
    )
    case library(
        path: AbsolutePath,
        publicHeaders: AbsolutePath,
        swiftModuleMap: AbsolutePath?,
        condition: PlatformCondition? = nil
    )
    case package(product: String, type: PackageType, condition: PlatformCondition? = nil)
    case sdk(name: String, status: LinkingStatus, condition: PlatformCondition? = nil)
    case xctest

    public var condition: PlatformCondition? {
        switch self {
        case .target(name: _, status: _, condition: let condition):
            condition
        case .project(target: _, path: _, status: _, condition: let condition):
            condition
        case .framework(path: _, status: _, condition: let condition):
            condition
        case .xcframework(path: _, expectedSignature: _, status: _, condition: let condition):
            condition
        case .library(path: _, publicHeaders: _, swiftModuleMap: _, condition: let condition):
            condition
        case .package(product: _, type: _, condition: let condition):
            condition
        case .sdk(name: _, status: _, condition: let condition):
            condition
        case .xctest: nil
        }
    }

    public func withCondition(_ condition: PlatformCondition?) -> TargetDependency {
        switch self {
        case .target(name: let name, status: let status, condition: _):
            return .target(name: name, status: status, condition: condition)
        case .project(target: let target, path: let path, status: let status, condition: _):
            return .project(target: target, path: path, status: status, condition: condition)
        case .framework(path: let path, status: let status, condition: _):
            return .framework(path: path, status: status, condition: condition)
        case .xcframework(path: let path, expectedSignature: let expectedSignature, status: let status, condition: _):
            return .xcframework(path: path, expectedSignature: expectedSignature, status: status, condition: condition)
        case .library(path: let path, publicHeaders: let headers, swiftModuleMap: let moduleMap, condition: _):
            return .library(path: path, publicHeaders: headers, swiftModuleMap: moduleMap, condition: condition)
        case .package(product: let product, type: let type, condition: _):
            return .package(product: product, type: type, condition: condition)
        case .sdk(name: let name, status: let status, condition: _):
            return .sdk(name: name, status: status, condition: condition)
        case .xctest: return .xctest
        }
    }
}
