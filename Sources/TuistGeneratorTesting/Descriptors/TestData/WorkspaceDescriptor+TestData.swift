import Foundation
import TSCBasic
import TuistCore
import XcodeProj

@testable import TuistGenerator

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
