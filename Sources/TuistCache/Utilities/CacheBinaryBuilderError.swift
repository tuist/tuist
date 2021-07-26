import TuistSupport

enum CacheBinaryBuilderError: FatalError {
    case nonFrameworkTargetForXCFramework(String)
    case nonFrameworkTargetForFramework(String)
    case nonBundleTarget(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .nonFrameworkTargetForXCFramework: return .abort
        case .nonFrameworkTargetForFramework: return .abort
        case .nonBundleTarget: return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .nonFrameworkTargetForXCFramework(name):
            return "Can't generate an .xcframework from the target '\(name)' because it's not a framework target"
        case let .nonFrameworkTargetForFramework(name):
            return "Can't generate a .framework from the target '\(name)' because it's not a framework target"
        case let .nonBundleTarget(name):
            return "Can't generate a .bundle from the target '\(name)' because it's not a bundle target"
        }
    }
}
