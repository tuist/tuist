import Foundation

public enum LinkingStatus: String, Codable, Sendable {
    case required
    case optional
}

@available(*, deprecated, renamed: "LinkingStatus")
typealias FrameworkStatus = LinkingStatus

@available(*, deprecated, renamed: "LinkingStatus")
typealias SDKStatus = LinkingStatus

public enum TargetDependency: Equatable, Hashable, Codable, Sendable {
    case target(name: String)
    case project(target: String, path: String)
    case framework(path: String, status: LinkingStatus)
    case xcframework(path: String, status: LinkingStatus)
    case library(path: String, publicHeaders: String, swiftModuleMap: String?)
    case package(product: String)
    case packagePlugin(product: String)
    case packageMacro(product: String)
    case sdk(name: String, status: LinkingStatus)
    case xctest
}
