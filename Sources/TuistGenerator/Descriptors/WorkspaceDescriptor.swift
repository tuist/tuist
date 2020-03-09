import Basic
import Foundation
import XcodeProj

public struct WorkspaceDescriptor {
    /// Path to the workspace
    public var path: AbsolutePath

    /// Path to the xcworkspace file
    public var xcworkspacePath: AbsolutePath
    public var xcworkspace: XCWorkspace
    public var projectDescriptors: [ProjectDescriptor]
    public var schemeDescriptors: [SchemeDescriptor]
    public var sideEffectDescriptors: [SideEffectDescriptor]

    public init(path: AbsolutePath,
                xcworkspacePath: AbsolutePath,
                xcworkspace: XCWorkspace,
                projectDescriptors: [ProjectDescriptor],
                schemeDescriptors: [SchemeDescriptor],
                sideEffectDescriptors: [SideEffectDescriptor]) {
        self.path = path
        self.xcworkspacePath = xcworkspacePath
        self.xcworkspace = xcworkspace
        self.projectDescriptors = projectDescriptors
        self.schemeDescriptors = schemeDescriptors
        self.sideEffectDescriptors = sideEffectDescriptors
    }
}
