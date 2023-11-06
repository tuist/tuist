import Foundation

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
    case project(target: String, path: String)
    case framework(path: String, status: FrameworkStatus)
    case xcframework(path: String, status: FrameworkStatus)
    case library(path: String, publicHeaders: String, swiftModuleMap: String?)
    case package(product: String)
    case packagePlugin(product: String)
    case packageMacro(product: String)
    case sdk(name: String, status: SDKStatus)
    case xctest
}
