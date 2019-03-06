import Basic
import Foundation
import TuistCore
import xcodeproj
@testable import TuistKit

class MockTargetGenerator: TargetGenerating {
    var generateTargetStub: (() -> PBXNativeTarget)?

    func generateTarget(target: Target, pbxproj: PBXProj, pbxProject: PBXProject, groups _: ProjectGroups, fileElements: ProjectFileElements, path: AbsolutePath, sourceRootPath: AbsolutePath, options: GenerationOptions, graph: Graphing, system: Systeming) throws -> PBXNativeTarget {
        return generateTargetStub?() ?? PBXNativeTarget(name: target.name)
    }

    func generateTargetDependencies(path _: AbsolutePath, targets _: [Target], nativeTargets _: [String: PBXNativeTarget], graph _: Graphing) throws {}
}
