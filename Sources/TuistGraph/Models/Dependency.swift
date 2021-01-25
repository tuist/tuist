import Foundation
import TSCBasic

public enum SDKStatus {
    case required
    case optional
}

public enum Dependency: Equatable, Hashable {
    case target(name: String)
    case project(target: String, path: AbsolutePath)
    case framework(path: AbsolutePath)
    case xcFramework(path: AbsolutePath)
    case library(path: AbsolutePath, publicHeaders: AbsolutePath, swiftModuleMap: AbsolutePath?)
    case package(product: String)
    case sdk(name: String, status: SDKStatus)
    case cocoapods(path: AbsolutePath)
    case xctest
}
