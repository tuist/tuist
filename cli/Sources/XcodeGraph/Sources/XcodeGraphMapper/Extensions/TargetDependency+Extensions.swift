import XcodeGraph

extension TargetDependency {
    /// Extracts the name of the dependency for relevant cases, such as target, project, SDK, package, and libraries.
    var name: String {
        switch self {
        case let .target(name, _, _):
            return name
        case let .project(target, _, _, _):
            return target
        case let .sdk(name, _, _):
            return name
        case let .package(product, _, _):
            return product
        case let .framework(path, _, _):
            return path.basenameWithoutExt
        case let .xcframework(path, _, _, _):
            return path.basenameWithoutExt
        case let .library(path, _, _, _):
            return path.basenameWithoutExt
        case .xctest:
            return "xctest"
        }
    }
}
