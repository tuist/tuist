
import Basic
import Foundation
import XcodeProj
@testable import TuistGenerator

extension GeneratedWorkspaceDescriptor {
    static func test(path: AbsolutePath = AbsolutePath("/Test/Project.xcworkspace"),
                     projects: [GeneratedProjectDescriptor] = [],
                     schemes: [GeneratedSchemeDescriptor] = [],
                     sideEffects: [GeneratedSideEffect] = []) -> GeneratedWorkspaceDescriptor {
        GeneratedWorkspaceDescriptor(path: path,
                                     xcworkspace: XCWorkspace(),
                                     projects: projects,
                                     schemes: schemes,
                                     sideEffects: sideEffects)
    }
}
