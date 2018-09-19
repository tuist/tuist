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
                                 options: GenerationOptions,
                                 resourceLocator: ResourceLocating) throws

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
    let manifestLoader: GraphManifestLoading

    // MARK: - Init

    init(configGenerator: ConfigGenerating = ConfigGenerator(),
         fileGenerator: FileGenerating = FileGenerator(),
         buildPhaseGenerator: BuildPhaseGenerating = BuildPhaseGenerator(),
         moduleLoader: GraphModuleLoading = GraphModuleLoader(),
         linkGenerator: LinkGenerating = LinkGenerator(),
         manifestLoader: GraphManifestLoading = GraphManifestLoader()) {
        self.configGenerator = configGenerator
        self.fileGenerator = fileGenerator
        self.buildPhaseGenerator = buildPhaseGenerator
        self.moduleLoader = moduleLoader
        self.linkGenerator = linkGenerator
        self.manifestLoader = manifestLoader
    }

    // MARK: - TargetGenerating

    func generateManifestsTarget(project: Project,
                                 pbxproj: PBXProj,
                                 pbxProject: PBXProject,
                                 groups: ProjectGroups,
                                 sourceRootPath: AbsolutePath,
                                 options: GenerationOptions,
                                 resourceLocator: ResourceLocating = ResourceLocator()) throws {
        /// Names
        let name = "\(project.name)Description"
        let frameworkName = "\(name).framework"

        /// Products reference.
        let productFileReference = PBXFileReference(sourceTree: .buildProductsDir, name: frameworkName)
        pbxproj.objects.add(object: productFileReference)
        groups.products.children.append(productFileReference)

        /// Files
        var files: [PBXFileElement] = []
        let projectManifestPath = try manifestLoader.manifestPath(at: project.path, manifest: .project)
        let modulePaths = try moduleLoader.load(projectManifestPath)
        try modulePaths.forEach { filePath in
            let fileReference = try fileGenerator.generateFile(path: filePath,
                                                               in: groups.projectDescription,
                                                               sourceRootPath: sourceRootPath)
            files.append(fileReference)
        }

        // Configuration
        let configurationList = try configGenerator.generateManifestsConfig(pbxproj: pbxproj,
                                                                            options: options,
                                                                            resourceLocator: resourceLocator)

        // Build phases
        let sourcesPhase = PBXSourcesBuildPhase()
        pbxproj.objects.add(object: sourcesPhase)
        try files.forEach({ _ = try sourcesPhase.addFile($0) })

        // Target
        let target = PBXNativeTarget(name: name,
                                     buildConfigurationList: configurationList,
                                     buildPhases: [sourcesPhase],
                                     buildRules: [],
                                     dependencies: [],
                                     productInstallPath: nil,
                                     productName: frameworkName,
                                     product: productFileReference,
                                     productType: .framework)
        pbxproj.objects.add(object: target)
        pbxProject.targets.append(target)
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
                                        buildConfigurationList: nil,
                                        buildPhases: [],
                                        buildRules: [],
                                        dependencies: [],
                                        productInstallPath: nil,
                                        productName: target.productName,
                                        product: productFileReference,
                                        productType: target.product.xcodeValue)
        objects.add(object: pbxTarget)
        pbxProject.targets.append(pbxTarget)

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
