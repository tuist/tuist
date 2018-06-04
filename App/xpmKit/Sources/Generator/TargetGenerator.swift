import Basic
import Foundation
import xcodeproj

/// Interface for targets generation.
protocol TargetGenerating: AnyObject {
    /// Generates the manifests target.
    ///
    /// - Parameters:
    ///   - project: Project spec.
    ///   - pbxproj: PBXProj instance from the generated Xcode project.
    ///   - pbxProject: PBXProject instance from the generated project.
    ///   - groups: Project groups.
    ///   - sourceRootPath: Path to the folder that contains the project that is getting generated.
    ///   - context: generation context.
    ///   - options: Generation options.
    /// - Throws: an error if the generation fails.
    func generateManifestsTarget(project: Project,
                                 pbxproj: PBXProj,
                                 pbxProject: PBXProject,
                                 groups: ProjectGroups,
                                 sourceRootPath: AbsolutePath,
                                 context: GeneratorContexting,
                                 options: GenerationOptions) throws

    /// Generates a native target.
    ///
    /// - Parameters:
    ///   - target: Target spec.
    ///   - objects: Xcode project objects.
    ///   - pbxProject: PBXProject instance from the generated project.
    ///   - groups: Project groups.
    ///   - fileElements: Project file elements.
    ///   - sourceRootPath: Path to the folder that contains the project that is getting generated.
    ///   - context: generation context.
    ///   - path: Path to the folder that contains the project manifest.
    ///   - sourceRootPath: Path to the folder that contains the Xcode project that is generated.
    /// - Returns: native target.
    func generateTarget(target targetSpec: Target,
                        objects: PBXObjects,
                        pbxProject: PBXProject,
                        groups: ProjectGroups,
                        fileElements: ProjectFileElements,
                        context: GeneratorContexting,
                        path: AbsolutePath,
                        sourceRootPath: AbsolutePath) throws -> PBXNativeTarget

    /// Generates the targets dependencies.
    ///
    /// - Parameters:
    ///   - path: path to the folder where the project manifest is.
    ///   - targets: project targets specs.
    ///   - nativeTargets: generated native targes in the Xcode project.
    ///   - objects: Xcode project objects.
    ///   - graph: dependencies graph.
    /// - Throws: an error if it fails generating the target dependencies.
    func generateTargetDependencies(path: AbsolutePath,
                                    targets: [Target],
                                    nativeTargets: [String: PBXNativeTarget],
                                    graph: Graphing) throws
}

/// Target generator.
final class TargetGenerator: TargetGenerating {
    /// Config generator.
    let configGenerator: ConfigGenerating

    /// Build phase generator.
    let buildPhaseGenerator: BuildPhaseGenerating

    /// Link generator.
    let linkGenerator: LinkGenerating

    /// File generator.
    let fileGenerator: FileGenerating

    /// Module loader.
    let moduleLoader: GraphModuleLoading

    /// Initializes the target generator with its attributes.
    ///
    /// - Parameters:
    ///   - configGenerator: config generator.
    ///   - fileGenerator: file generator.
    ///   - buildPhaseGenerator: build phase generator.
    ///   - linkGenerator: link generator.
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

    /// Generates the manifests target.
    ///
    /// - Parameters:
    ///   - project: Project spec.
    ///   - pbxproj: PBXProj instance from the generated Xcode project.
    ///   - pbxProject: PBXProject instance from the generated project.
    ///   - groups: Project groups.
    ///   - sourceRootPath: Path to the folder that contains the project that is getting generated.
    ///   - context: generation context.
    ///   - options: generation options.
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
        groups.products.children.append(productFileReferenceRef)

        /// Files
        var files: [PBXObjectReference] = []
        let projectManifestPath = project.path.appending(component: Constants.Manifest.project)
        let modulePaths = try moduleLoader.load(projectManifestPath, context: context)
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
        let sourcesPhase = PBXSourcesBuildPhase(files: [])
        let sourcesPhaseReference = pbxproj.objects.addObject(sourcesPhase)
        try files.forEach({ _ = try sourcesPhase.addFile($0) })

        // Target
        let target = PBXNativeTarget(name: name,
                                     buildConfigurationListRef: configurationListReference,
                                     buildPhases: [sourcesPhaseReference],
                                     productName: frameworkName,
                                     productReference: productFileReferenceRef,
                                     productType: .framework)
        let targetReference = pbxproj.objects.addObject(target)
        pbxProject.targets.append(targetReference)
    }

    /// Generates a native target.
    ///
    /// - Parameters:
    ///   - target: Target spec.
    ///   - objects: Xcode project objects.
    ///   - pbxProject: PBXProject instance from the generated project.
    ///   - groups: Project groups.
    ///   - fileElements: Project file elements.
    ///   - sourceRootPath: Path to the folder that contains the project that is getting generated.
    ///   - context: generation context.
    ///   - path: Path to the folder that contains the project manifest.
    ///   - sourceRootPath: path to the folder where the Xcode project is generated.
    /// - Returns: native target.
    func generateTarget(target: Target,
                        objects: PBXObjects,
                        pbxProject: PBXProject,
                        groups _: ProjectGroups,
                        fileElements: ProjectFileElements,
                        context: GeneratorContexting,
                        path: AbsolutePath,
                        sourceRootPath: AbsolutePath) throws -> PBXNativeTarget {
        /// Products reference.
        let productFileReference = fileElements.products[target.productName]!

        /// Target
        let pbxTarget = PBXNativeTarget(name: target.name,
                                        buildConfigurationListRef: nil,
                                        buildPhases: [],
                                        buildRules: [],
                                        dependencies: [],
                                        productName: target.productName,
                                        productReference: productFileReference.reference,
                                        productType: target.product.xcodeValue)
        let targetReference = objects.addObject(pbxTarget)
        pbxProject.targets.append(targetReference)

        /// Build phases
        try buildPhaseGenerator.generateBuildPhases(target: target,
                                                    pbxTarget: pbxTarget,
                                                    fileElements: fileElements,
                                                    objects: objects)

        /// Links
        try linkGenerator.generateLinks(target: target,
                                        pbxTarget: pbxTarget,
                                        context: context,
                                        objects: objects,
                                        pbxProject: pbxProject,
                                        fileElements: fileElements,
                                        path: path,
                                        sourceRootPath: sourceRootPath)
        return pbxTarget
    }

    /// Generates the targets dependencies.
    ///
    /// - Parameters:
    ///   - path: path to the folder where the project manifest is.
    ///   - targets: project targets specs.
    ///   - nativeTargets: generated native targes in the Xcode project.
    ///   - objects: Xcode project objects.
    ///   - graph: dependencies graph.
    /// - Throws: an error if it fails generating the target dependencies
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
