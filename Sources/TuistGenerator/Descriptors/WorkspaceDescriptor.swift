import Basic
import Foundation
import XcodeProj

public struct WorkspaceDescriptor {
    /// Path to the xcworkspace file
    public var path: AbsolutePath
    public var xcworkspace: XCWorkspace
    public var projects: [ProjectDescriptor]
    public var schemes: [SchemeDescriptor]
    public var sideEffects: [SideEffect]
}
