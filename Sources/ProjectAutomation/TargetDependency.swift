import Foundation

public enum LinkingStatus: String, Codable, Sendable {
    case required
    case optional
    case none
}

@available(*, deprecated, renamed: "LinkingStatus")
typealias FrameworkStatus = LinkingStatus

@available(*, deprecated, renamed: "LinkingStatus")
typealias SDKStatus = LinkingStatus

public enum TargetDependency: Equatable, Hashable, Codable, Sendable {
    case target(name: String, status: LinkingStatus)
    case macro(name: String)
    case project(target: String, path: String, status: LinkingStatus)
    case framework(path: String, status: LinkingStatus)
    case xcframework(path: String, status: LinkingStatus)
    case library(path: String, publicHeaders: String, swiftModuleMap: String?)
    case package(product: String, embedded: Bool = false)
    case packagePlugin(product: String)
    case packageMacro(product: String)
    case sdk(name: String, status: LinkingStatus)
    case xctest
}
