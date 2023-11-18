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

    case target(name: String, platformFilters: PlatformFilters = .all)
    case project(target: String, path: AbsolutePath, platformFilters: PlatformFilters = .all)
    case framework(path: AbsolutePath, status: FrameworkStatus, platformFilters: PlatformFilters = .all)
    case xcframework(path: AbsolutePath, status: FrameworkStatus, platformFilters: PlatformFilters = .all)
    case library(
        path: AbsolutePath,
        publicHeaders: AbsolutePath,
        swiftModuleMap: AbsolutePath?,
        platformFilters: PlatformFilters = .all
    )
    case package(product: String, type: PackageType, platformFilters: PlatformFilters = .all)
    case sdk(name: String, status: SDKStatus, platformFilters: PlatformFilters = .all)
    case xctest

    public var platformFilters: PlatformFilters {
        switch self {
        case .target(name: _, platformFilters: let platformFilters):
            platformFilters
        case .project(target: _, path: _, platformFilters: let platformFilters):
            platformFilters
        case .framework(path: _, status: _, platformFilters: let platformFilters):
            platformFilters
        case .xcframework(path: _, status: _, platformFilters: let platformFilters):
            platformFilters
        case .library(path: _, publicHeaders: _, swiftModuleMap: _, platformFilters: let platformFilters):
            platformFilters
        case .package(product: _, type: _, platformFilters: let platformFilters):
            platformFilters
        case .sdk(name: _, status: _, platformFilters: let platformFilters):
            platformFilters
        case .xctest: .all
        }
    }

    public func withFilters(_ platformFilters: PlatformFilters) -> TargetDependency {
        switch self {
        case .target(name: let name, platformFilters: _):
            return .target(name: name, platformFilters: platformFilters)
        case .project(target: let target, path: let path, platformFilters: _):
            return .project(target: target, path: path, platformFilters: platformFilters)
        case .framework(path: let path, status: let status, platformFilters: _):
            return .framework(path: path, status: status, platformFilters: platformFilters)
        case .xcframework(path: let path, status: let status, platformFilters: _):
            return .xcframework(path: path, status: status, platformFilters: platformFilters)
        case .library(path: let path, publicHeaders: let headers, swiftModuleMap: let moduleMap, platformFilters: _):
            return .library(path: path, publicHeaders: headers, swiftModuleMap: moduleMap, platformFilters: platformFilters)
        case .package(product: let product, type: let type, platformFilters: _):
            return .package(product: product, type: type, platformFilters: platformFilters)
        case .sdk(name: let name, status: let status, platformFilters: _):
            return .sdk(name: name, status: status, platformFilters: platformFilters)
        case .xctest: return .xctest
        }
    }
}
