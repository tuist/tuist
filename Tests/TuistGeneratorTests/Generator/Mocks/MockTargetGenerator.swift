import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeProj
@testable import TuistGenerator

class MockTargetGenerator: TargetGenerating {
    var generateTargetStub: (() -> PBXNativeTarget)?

    func generateTarget(target: Target, project _: Project, pbxproj _: PBXProj, pbxProject _: PBXProject, projectSettings _: Settings, fileElements _: ProjectFileElements, path _: AbsolutePath, sourceRootPath _: AbsolutePath, graph _: Graph) throws -> PBXNativeTarget {
        generateTargetStub?() ?? PBXNativeTarget(name: target.name)
    }

    func generateTargetDependencies(path _: AbsolutePath, targets _: [Target], nativeTargets _: [String: PBXNativeTarget], graph _: Graph) throws {}
}
