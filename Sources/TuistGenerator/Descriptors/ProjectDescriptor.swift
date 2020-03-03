import Basic
import Foundation
import XcodeProj

public struct GeneratedProjectDescriptor {
    /// Path to the xcodeproj file
    public var path: AbsolutePath
    public var xcodeProj: XcodeProj
    public var schemes: [GeneratedSchemeDescriptor]
    public var sideEffects: [GeneratedSideEffect]
}
