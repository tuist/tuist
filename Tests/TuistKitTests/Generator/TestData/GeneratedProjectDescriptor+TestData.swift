
import Basic
import Foundation
import XcodeProj
@testable import TuistGenerator

extension ProjectDescriptor {
    static func test(path: AbsolutePath = AbsolutePath("/Test/Project.xcodeproj"),
                     schemes: [SchemeDescriptor] = [],
                     sideEffects: [SideEffect] = []) -> ProjectDescriptor {
        let xcodeProj = XcodeProj(workspace: XCWorkspace(), pbxproj: PBXProj())
        return ProjectDescriptor(path: path,
                                 xcodeProj: xcodeProj,
                                 schemes: schemes,
                                 sideEffects: sideEffects)
    }
}
