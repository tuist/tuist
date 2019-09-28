import Basic
import Foundation
import TuistCore
import XcodeProj

protocol TargetGenerating: AnyObject {
    func generateTarget(target: Target,
                        pbxproj: PBXProj,
                        pbxProject: PBXProject,
                        projectSettings: Settings,
                        fileElements: ProjectFileElements,
                        path: AbsolutePath,
                        sourceRootPath: AbsolutePath,
                        graph: Graphing,
                        system: Systeming) throws -> PBXNativeTarget

    func generateTargetDependencies(path: AbsolutePath,
                                    targets: [Target],
                                    nativeTargets: [String: PBXNativeTarget],
                                    graph: Graphing) throws
}

final class TargetGenerator: TargetGenerating {
    // MARK: - Attributes

    let configGenerator: ConfigGenerating
    let buildPhaseGenerator: BuildPhaseGenerating
    let linkGenerator: LinkGenerating
    let fileGenerator: FileGenerating

    // MARK: - Init

    init(configGenerator: ConfigGenerating = ConfigGenerator(),
         fileGenerator: FileGenerating = FileGenerator(),
         buildPhaseGenerator: BuildPhaseGenerating = BuildPhaseGenerator(),
         linkGenerator: LinkGenerating = LinkGenerator()) {
        self.configGenerator = configGenerator
        self.fileGenerator = fileGenerator
        self.buildPhaseGenerator = buildPhaseGenerator
        self.linkGenerator = linkGenerator
    }

    // MARK: - TargetGenerating

    // swiftlint:disable:next function_body_length
    func generateTarget(target: Target,
                        pbxproj: PBXProj,
                        pbxProject: PBXProject,
                        projectSettings: Settings,
                        fileElements: ProjectFileElements,
                        path: AbsolutePath,
                        sourceRootPath: AbsolutePath,
                        graph: Graphing,
                        system: Systeming = System()) throws -> PBXNativeTarget {
        /// Products reference.
        let productFileReference = fileElements.products[target.name]!

        /// Target
        let pbxTarget = PBXNativeTarget(name: target.name,
                                        buildConfigurationList: nil,
                                        buildPhases: [],
                                        buildRules: [],
                                        dependencies: [],
                                        productInstallPath: nil,
                                        productName: target.productName,
                                        product: productFileReference,
                                        productType: target.product.xcodeValue)
        pbxproj.add(object: pbxTarget)
        pbxProject.targets.append(pbxTarget)

        /// Pre actions
        try buildPhaseGenerator.generateActions(actions: target.actions.preActions,
                                                pbxTarget: pbxTarget,
                                                pbxproj: pbxproj,
                                                sourceRootPath: sourceRootPath)

        /// Build configuration
        try configGenerator.generateTargetConfig(target,
                                                 pbxTarget: pbxTarget,
                                                 pbxproj: pbxproj,
                                                 projectSettings: projectSettings,
                                                 fileElements: fileElements,
                                                 graph: graph,
                                                 sourceRootPath: sourceRootPath)

        /// Build phases
        try buildPhaseGenerator.generateBuildPhases(path: path,
                                                    target: target,
                                                    graph: graph,
                                                    pbxTarget: pbxTarget,
                                                    fileElements: fileElements,
                                                    pbxproj: pbxproj,
                                                    sourceRootPath: sourceRootPath)

        /// Links
        try linkGenerator.generateLinks(target: target,
                                        pbxTarget: pbxTarget,
                                        pbxproj: pbxproj,
                                        pbxProject: pbxProject,
                                        fileElements: fileElements,
                                        path: path,
                                        sourceRootPath: sourceRootPath,
                                        graph: graph,
                                        system: system)

        /// Post actions
        try buildPhaseGenerator.generateActions(actions: target.actions.postActions,
                                                pbxTarget: pbxTarget,
                                                pbxproj: pbxproj,
                                                sourceRootPath: sourceRootPath)
        return pbxTarget
    }

    func generateTargetDependencies(path: AbsolutePath,
                                    targets: [Target],
                                    nativeTargets: [String: PBXNativeTarget],
                                    graph: Graphing) throws {
        try targets.forEach { targetSpec in
            let dependencies = graph.targetDependencies(path: path, name: targetSpec.name)
            try dependencies.forEach { dependency in
                let target = nativeTargets[targetSpec.name]!
                let dependency = nativeTargets[dependency.target.name]!
                _ = try target.addDependency(target: dependency)
            }
        }
    }
}
