import Foundation
import TSCBasic

public enum FrameworkStatus: String, Codable {
    case required
    case optional
}

public enum SDKStatus: String, Codable {
    case required
    case optional
}

public enum TargetDependency: Equatable, Hashable, Codable {
    public enum PackageType: String, Equatable, Hashable, Codable {
        case runtime
        case plugin
        case macro
    }

    case target(name: String, condition: PlatformCondition? = nil)
    case project(target: String, path: AbsolutePath, condition: PlatformCondition? = nil)
    case framework(path: AbsolutePath, status: FrameworkStatus, condition: PlatformCondition? = nil)
    case xcframework(path: AbsolutePath, status: FrameworkStatus, condition: PlatformCondition? = nil)
    case library(
        path: AbsolutePath,
        publicHeaders: AbsolutePath,
        swiftModuleMap: AbsolutePath?,
        condition: PlatformCondition? = nil
    )
    case package(product: String, type: PackageType, condition: PlatformCondition? = nil)
    case sdk(name: String, status: SDKStatus, condition: PlatformCondition? = nil)
    case xctest

    public var condition: PlatformCondition? {
        switch self {
        case .target(name: _, condition: let condition):
            condition
        case .project(target: _, path: _, condition: let condition):
            condition
        case .framework(path: _, status: _, condition: let condition):
            condition
        case .xcframework(path: _, status: _, condition: let condition):
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
        case .target(name: let name, condition: _):
            return .target(name: name, condition: condition)
        case .project(target: let target, path: let path, condition: _):
            return .project(target: target, path: path, condition: condition)
        case .framework(path: let path, status: let status, condition: _):
            return .framework(path: path, status: status, condition: condition)
        case .xcframework(path: let path, status: let status, condition: _):
            return .xcframework(path: path, status: status, condition: condition)
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
