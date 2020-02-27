import Basic
import Foundation
import XcodeProj

public struct GeneratedWorkspaceDescriptor {
    /// Path to the xcworkspace file
    public var path: AbsolutePath
    public var xcworkspace: XCWorkspace
    public var projects: [GeneratedProjectDescriptor]
    public var schemes: [GeneratedSchemeDescriptor]
    public var sideEffects: [GeneratedSideEffect]
}
