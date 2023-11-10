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

    case target(name: String)
    case project(target: String, path: AbsolutePath)
    case framework(path: AbsolutePath, status: FrameworkStatus)
    case xcframework(path: AbsolutePath, status: FrameworkStatus)
    case library(path: AbsolutePath, publicHeaders: AbsolutePath, swiftModuleMap: AbsolutePath?)
    case package(product: String, type: PackageType)
    case sdk(name: String, status: SDKStatus)
    case xctest
}
