
import Basic
import Foundation
import XcodeProj
@testable import TuistGenerator

extension ProjectDescriptor {
    static func test(path: AbsolutePath = AbsolutePath("/Test"),
                     xcodeprojPath: AbsolutePath = AbsolutePath("/Test/Project.xcodeproj"),
                     schemes: [SchemeDescriptor] = [],
                     sideEffects: [SideEffectDescriptor] = []) -> ProjectDescriptor {
        let xcodeProj = XcodeProj(workspace: XCWorkspace(), pbxproj: PBXProj())
        return ProjectDescriptor(path: path,
                                 xcodeprojPath: xcodeprojPath,
                                 xcodeProj: xcodeProj,
                                 schemeDescriptors: schemes,
                                 sideEffectDescriptors: sideEffects)
    }
}
