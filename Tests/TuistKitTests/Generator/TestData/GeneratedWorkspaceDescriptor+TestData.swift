
import Basic
import Foundation
import XcodeProj
@testable import TuistGenerator

extension WorkspaceDescriptor {
    static func test(path: AbsolutePath = AbsolutePath("/Test/Project.xcworkspace"),
                     projects: [ProjectDescriptor] = [],
                     schemes: [SchemeDescriptor] = [],
                     sideEffects: [SideEffect] = []) -> WorkspaceDescriptor {
        WorkspaceDescriptor(path: path,
                            xcworkspace: XCWorkspace(),
                            projects: projects,
                            schemes: schemes,
                            sideEffects: sideEffects)
    }
}
