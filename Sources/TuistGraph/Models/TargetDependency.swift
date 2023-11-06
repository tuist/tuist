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
    case target(name: String)
    case project(target: String, path: AbsolutePath)
    case framework(path: AbsolutePath, status: FrameworkStatus)
    case xcframework(path: AbsolutePath, status: FrameworkStatus)
    case library(path: AbsolutePath, publicHeaders: AbsolutePath, swiftModuleMap: AbsolutePath?)
    case package(product: String)
    case packagePlugin(product: String)
    case packageMacro(product: String)
    case sdk(name: String, status: SDKStatus)
    case xctest
}
