import XcodeGraph

extension TargetDependency {
    var hasSignature: Bool {
        switch self {
        case let .xcframework(_, expectedSignature, _, _):
            expectedSignature != nil
        default:
            false
        }
    }
}
