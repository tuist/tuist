import Basic
import Foundation
import TuistCore
import xcodeproj
@testable import TuistKit

class MockTargetGenerator: TargetGenerating {
    var generateTargetStub: (() -> PBXNativeTarget)?

    func generateManifestsTarget(project _: Project, pbxproj _: PBXProj, pbxProject _: PBXProject, groups _: ProjectGroups, sourceRootPath _: AbsolutePath, options _: GenerationOptions, resourceLocator _: ResourceLocating) throws {}

    func generateTarget(target: Target, pbxproj: PBXProj, pbxProject: PBXProject, groups _: ProjectGroups, fileElements: ProjectFileElements, path: AbsolutePath, sourceRootPath: AbsolutePath, options: GenerationOptions, graph: Graphing, resourceLocator: ResourceLocating, system: Systeming) throws -> PBXNativeTarget {
        return generateTargetStub?() ?? PBXNativeTarget(name: target.name)
    }

    func generateTargetDependencies(path _: AbsolutePath, targets _: [Target], nativeTargets _: [String: PBXNativeTarget], graph _: Graphing) throws {}
}
