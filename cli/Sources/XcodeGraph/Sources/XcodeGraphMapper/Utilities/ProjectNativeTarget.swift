import XcodeProj

/// Model representing a `PBXNativeTarget` in a give `XcodeProj`
struct ProjectNativeTarget: Equatable {
    let nativeTarget: PBXNativeTarget
    let project: XcodeProj
}
