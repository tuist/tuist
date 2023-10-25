import Foundation
import TSCBasic

public enum SDKStatus: String, Codable {
    case required
    case optional
}

public enum TargetDependency: Equatable, Hashable, Codable {
    case target(name: String)
    case project(target: String, path: AbsolutePath)
    case framework(path: AbsolutePath, required: Bool)
    case xcframework(path: AbsolutePath, required: Bool)
    case library(path: AbsolutePath, publicHeaders: AbsolutePath, swiftModuleMap: AbsolutePath?)
    case package(product: String)
    case packagePlugin(product: String)
    case sdk(name: String, status: SDKStatus)
    case xctest
}
