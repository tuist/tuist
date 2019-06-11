import Basic
import Foundation

public enum SDKStatus {
    case required
    case optional
}

public enum Dependency: Equatable {
    case target(name: String)
    case project(target: String, path: RelativePath)
    case framework(path: RelativePath)
    case library(path: RelativePath, publicHeaders: RelativePath, swiftModuleMap: RelativePath?)
    case sdk(name: String, status: SDKStatus)
}
