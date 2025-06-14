import Foundation
import Path
import TuistCore
import XcodeProj

/// Workspace Descriptor
///
/// Contains the information needed to generate a workspace
/// and all its projects.
///
/// Can be used in conjunction with `XcodeProjWriter` to
/// generate an `.xcworkspace` file along with all its
/// `.xcodeproj` files.
///
/// - seealso: `XcodeProjWriter`
public struct WorkspaceDescriptor {
    /// Path to the workspace
    public var path: AbsolutePath

    /// Path to the xcworkspace file
    public var xcworkspacePath: AbsolutePath

    /// The XCWorkspace representation of the workspace
    public var xcworkspace: XCWorkspace

    /// The project descriptors of all the projects within this workspace
    public var projectDescriptors: [ProjectDescriptor]

    /// The scheme descriptors of all the schemes within this workspace
    public var schemeDescriptors: [SchemeDescriptor]

    /// The side effects required for generating this workspace
    public var sideEffectDescriptors: [SideEffectDescriptor]

    /// The descriptor used to generate workspace settings (WorkspaceSettings.xcsettings)
    public var workspaceSettingsDescriptor: WorkspaceSettingsDescriptor?

    public init(
        path: AbsolutePath,
        xcworkspacePath: AbsolutePath,
        xcworkspace: XCWorkspace,
        projectDescriptors: [ProjectDescriptor],
        schemeDescriptors: [SchemeDescriptor],
        sideEffectDescriptors: [SideEffectDescriptor],
        workspaceSettingsDescriptor: WorkspaceSettingsDescriptor? = nil
    ) {
        self.path = path
        self.xcworkspacePath = xcworkspacePath
        self.xcworkspace = xcworkspace
        self.workspaceSettingsDescriptor = workspaceSettingsDescriptor
        self.projectDescriptors = projectDescriptors
        self.schemeDescriptors = schemeDescriptors
        self.sideEffectDescriptors = sideEffectDescriptors
    }
}

#if DEBUG
    extension WorkspaceDescriptor {
        public static func test(
            path: AbsolutePath = try! AbsolutePath(validating: "/Test"), // swiftlint:disable:this force_try
            // swiftlint:disable:next force_try
            xcworkspacePath: AbsolutePath = try! AbsolutePath(validating: "/Test/Project.xcworkspace"),
            projects: [ProjectDescriptor] = [],
            schemes: [SchemeDescriptor] = [],
            sideEffects: [SideEffectDescriptor] = []
        ) -> WorkspaceDescriptor {
            WorkspaceDescriptor(
                path: path,
                xcworkspacePath: xcworkspacePath,
                xcworkspace: XCWorkspace(),
                projectDescriptors: projects,
                schemeDescriptors: schemes,
                sideEffectDescriptors: sideEffects
            )
        }
    }
#endif
