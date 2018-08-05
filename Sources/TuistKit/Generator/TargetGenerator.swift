import Basic
import Foundation
import TuistCore
import xcodeproj

protocol TargetGenerating: AnyObject {
    func generateManifestsTarget(project: Project,
                                 pbxproj: PBXProj,
                                 pbxProject: PBXProject,
                                 groups: ProjectGroups,
                                 sourceRootPath: AbsolutePath,
                                 context: GeneratorContexting,
                                 options: GenerationOptions) throws

    func generateTarget(target: Target,
                        objects: PBXObjects,
                        pbxProject: PBXProject,
                        groups _: ProjectGroups,
                        fileElements: ProjectFileElements,
                        path: AbsolutePath,
                        sourceRootPath: AbsolutePath,
                        options: GenerationOptions,
                        graph: Graphing,
                        resourceLocator: ResourceLocating,
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
    let moduleLoader: GraphModuleLoading

    // MARK: - Init

    init(configGenerator: ConfigGenerating = ConfigGenerator(),
         fileGenerator: FileGenerating = FileGenerator(),
         buildPhaseGenerator: BuildPhaseGenerating = BuildPhaseGenerator(),
         moduleLoader: GraphModuleLoading = GraphModuleLoader(),
         linkGenerator: LinkGenerating = LinkGenerator()) {
        self.configGenerator = configGenerator
        self.fileGenerator = fileGenerator
        self.buildPhaseGenerator = buildPhaseGenerator
        self.moduleLoader = moduleLoader
        self.linkGenerator = linkGenerator
    }

    // MARK: - TargetGenerating

    func generateManifestsTarget(project: Project,
                                 pbxproj: PBXProj,
                                 pbxProject: PBXProject,
                                 groups: ProjectGroups,
                                 sourceRootPath: AbsolutePath,
                                 context: GeneratorContexting,
                                 options: GenerationOptions) throws {
        /// Names
        let name = "\(project.name)Description"
        let frameworkName = "\(name).framework"

        /// Products reference.
        let productFileReference = PBXFileReference(sourceTree: .buildProductsDir, name: frameworkName)
        let productFileReferenceRef = pbxproj.objects.addObject(productFileReference)
        groups.products.childrenReferences.append(productFileReferenceRef)

        /// Files
        var files: [PBXObjectReference] = []
        let projectManifestPath = project.path.appending(component: Constants.Manifest.project)
        let modulePaths = try moduleLoader.load(projectManifestPath)
        try modulePaths.forEach { filePath in
            let fileReference = try fileGenerator.generateFile(path: filePath,
                                                               in: groups.projectDescription,
                                                               sourceRootPath: sourceRootPath,
                                                               context: context)
            files.append(fileReference.reference)
        }

        // Configuration
        let configurationListReference = try configGenerator.generateManifestsConfig(pbxproj: pbxproj,
                                                                                     context: context,
                                                                                     options: options)

        // Build phases
        let sourcesPhase = PBXSourcesBuildPhase()
        let sourcesPhaseReference = pbxproj.objects.addObject(sourcesPhase)
        try files.forEach({ _ = try sourcesPhase.addFile($0) })

        // Target
        let target = PBXNativeTarget(name: name,
                                     buildConfigurationListReference: configurationListReference,
                                     buildPhasesReferences: [sourcesPhaseReference],
                                     productName: frameworkName,
                                     productReference: productFileReferenceRef,
                                     productType: .framework)
        let targetReference = pbxproj.objects.addObject(target)
        pbxProject.targetsReferences.append(targetReference)
    }

    func generateTarget(target: Target,
                        objects: PBXObjects,
                        pbxProject: PBXProject,
                        groups _: ProjectGroups,
                        fileElements: ProjectFileElements,
                        path: AbsolutePath,
                        sourceRootPath: AbsolutePath,
                        options: GenerationOptions,
                        graph: Graphing,
                        resourceLocator: ResourceLocating = ResourceLocator(),
                        system: Systeming = System()) throws -> PBXNativeTarget {
        /// Products reference.
        let productFileReference = fileElements.products[target.productName]!

        /// Target
        let pbxTarget = PBXNativeTarget(name: target.name,
                                        buildConfigurationListReference: nil,
                                        buildPhasesReferences: [],
                                        buildRulesReferences: [],
                                        dependenciesReferences: [],
                                        productName: target.productName,
                                        productReference: productFileReference.reference,
                                        productType: target.product.xcodeValue)
        let targetReference = objects.addObject(pbxTarget)
        pbxProject.targetsReferences.append(targetReference)

        /// Build configuration
        try configGenerator.generateTargetConfig(target,
                                                 pbxTarget: pbxTarget,
                                                 objects: objects,
                                                 fileElements: fileElements,
                                                 options: options,
                                                 sourceRootPath: sourceRootPath)

        /// Build phases
        try buildPhaseGenerator.generateBuildPhases(target: target,
                                                    pbxTarget: pbxTarget,
                                                    fileElements: fileElements,
                                                    objects: objects)

        /// Links
        try linkGenerator.generateLinks(target: target,
                                        pbxTarget: pbxTarget,
                                        objects: objects,
                                        pbxProject: pbxProject,
                                        fileElements: fileElements,
                                        path: path,
                                        sourceRootPath: sourceRootPath,
                                        graph: graph,
                                        resourceLocator: resourceLocator,
                                        system: system)
        return pbxTarget
    }

    func generateTargetDependencies(path: AbsolutePath,
                                    targets: [Target],
                                    nativeTargets: [String: PBXNativeTarget],
                                    graph: Graphing) throws {
        try targets.forEach { targetSpec in
            let dependencies = graph.targetDependencies(path: path, name: targetSpec.name)
            try dependencies.forEach { dependencyName in
                let target = nativeTargets[targetSpec.name]!
                let dependency = nativeTargets[dependencyName]!
                _ = try target.addDependency(target: dependency)
            }
        }
    }
}
