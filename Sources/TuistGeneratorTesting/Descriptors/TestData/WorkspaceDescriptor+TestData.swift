import Foundation
import TSCBasic
import TuistCore
import XcodeProj

@testable import TuistGenerator

extension WorkspaceDescriptor {
    public static func test(
        path: AbsolutePath = try! AbsolutePath(validating: "/Test"),
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
