import Basic
import Foundation
import XcodeProj

public struct WorkspaceDescriptor {
    /// Path to the workspace
    public var path: AbsolutePath

    /// Path to the xcworkspace file
    public var xcworkspacePath: AbsolutePath
    public var xcworkspace: XCWorkspace
    public var projects: [ProjectDescriptor]
    public var schemes: [SchemeDescriptor]
    public var sideEffects: [SideEffect]

    public init(path: AbsolutePath,
                xcworkspacePath: AbsolutePath,
                xcworkspace: XCWorkspace,
                projects: [ProjectDescriptor],
                schemes: [SchemeDescriptor],
                sideEffects: [SideEffect]) {
        self.path = path
        self.xcworkspacePath = xcworkspacePath
        self.xcworkspace = xcworkspace
        self.projects = projects
        self.schemes = schemes
        self.sideEffects = sideEffects
    }
}
