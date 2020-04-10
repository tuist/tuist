import Basic
import Foundation
import TuistCore
import XcodeProj

@testable import TuistGenerator

public extension WorkspaceDescriptor {
    static func test(path: AbsolutePath = AbsolutePath("/Test"),
                     xcworkspacePath: AbsolutePath = AbsolutePath("/Test/Project.xcworkspace"),
                     projects: [ProjectDescriptor] = [],
                     schemes: [SchemeDescriptor] = [],
                     sideEffects: [SideEffectDescriptor] = []) -> WorkspaceDescriptor {
        WorkspaceDescriptor(path: path,
                            xcworkspacePath: xcworkspacePath,
                            xcworkspace: XCWorkspace(),
                            projectDescriptors: projects,
                            schemeDescriptors: schemes,
                            sideEffectDescriptors: sideEffects)
    }
}
