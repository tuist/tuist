import Basic
import Foundation
import TuistCore
import XcodeProj
@testable import TuistGenerator

class MockTargetGenerator: TargetGenerating {
    var generateTargetStub: (() -> PBXNativeTarget)?

    func generateTarget(target: Target, pbxproj _: PBXProj, pbxProject _: PBXProject, projectSettings _: Settings, fileElements _: ProjectFileElements, path _: AbsolutePath, sourceRootPath _: AbsolutePath, graph _: Graphing, system _: Systeming) throws -> PBXNativeTarget {
        return generateTargetStub?() ?? PBXNativeTarget(name: target.name)
    }

    func generateTargetDependencies(path _: AbsolutePath, targets _: [Target], nativeTargets _: [String: PBXNativeTarget], graph _: Graphing) throws {}
}
