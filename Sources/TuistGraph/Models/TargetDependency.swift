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

    case target(name: String, platformFilters: PlatformFilters = [])
    case project(target: String, path: AbsolutePath, platformFilters: PlatformFilters = [])
    case framework(path: AbsolutePath, status: FrameworkStatus, platformFilters: PlatformFilters = [])
    case xcframework(path: AbsolutePath, status: FrameworkStatus, platformFilters: PlatformFilters = [])
    case library(path: AbsolutePath, publicHeaders: AbsolutePath, swiftModuleMap: AbsolutePath?, platformFilters: PlatformFilters = [])
    case package(product: String, type: PackageType, platformFilters: PlatformFilters = [])
    case sdk(name: String, status: SDKStatus, platformFilters: PlatformFilters = [])
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
        case .xctest: []
        }
    }
}
