import Basic
import Foundation
import XcodeProj

public struct ProjectDescriptor {
    /// Path to the xcodeproj file
    public var path: AbsolutePath
    public var xcodeProj: XcodeProj
    public var schemes: [SchemeDescriptor]
    public var sideEffects: [SideEffect]
}
