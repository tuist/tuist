
import Basic
import Foundation
import XcodeProj
@testable import TuistGenerator

extension ProjectDescriptor {
    static func test(path: AbsolutePath = AbsolutePath("/Test"),
                     xcodeprojPath: AbsolutePath = AbsolutePath("/Test/Project.xcodeproj"),
                     schemes: [SchemeDescriptor] = [],
                     sideEffects: [SideEffect] = []) -> ProjectDescriptor {
        let xcodeProj = XcodeProj(workspace: XCWorkspace(), pbxproj: PBXProj())
        return ProjectDescriptor(path: path,
                                 xcodeprojPath: xcodeprojPath,
                                 xcodeProj: xcodeProj,
                                 schemes: schemes,
                                 sideEffects: sideEffects)
    }
}
