
import Basic
import Foundation
import XcodeProj
@testable import TuistGenerator

extension GeneratedProjectDescriptor {
    static func test(path: AbsolutePath = AbsolutePath("/Test/Project.xcodeproj"),
                     schemes: [GeneratedSchemeDescriptor] = [],
                     sideEffects: [GeneratedSideEffect] = []) -> GeneratedProjectDescriptor {
        let xcodeProj = XcodeProj(workspace: XCWorkspace(), pbxproj: PBXProj())
        return GeneratedProjectDescriptor(path: path,
                                          xcodeProj: xcodeProj,
                                          schemes: schemes,
                                          sideEffects: sideEffects)
    }
}
