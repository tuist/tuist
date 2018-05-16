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
    ///   - pbxproj: PBXProj instance from the generated Xcode project.
    ///   - pbxProject: PBXProject instance from the generated project.
    ///   - groups: Project groups.
    ///   - sourceRootPath: Path to the folder that contains the project that is getting generated.
    ///   - context: generation context.
    /// - Throws: an error if the generation fails.
    func generateTarget(target: Target,
                        pbxproj: PBXProj,
                        pbxProject: PBXProject,
                        groups: ProjectGroups,
                        sourceRootPath: AbsolutePath,
                        context: GeneratorContexting) throws
}

/// Target generator.
final class TargetGenerator: TargetGenerating {
    /// Config generator.
    let configGenerator: ConfigGenerating

    /// File generator.
    let fileGenerator: FileGenerating

    /// Initializes the target generator with its attributes.
    ///
    /// - Parameters:
    ///   - configGenerator: config generator.
    ///   - fileGenerator: file generator.
    init(configGenerator: ConfigGenerating = ConfigGenerator(),
         fileGenerator: FileGenerating = FileGenerator()) {
        self.configGenerator = configGenerator
        self.fileGenerator = fileGenerator
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
    /// - Throws: an error if the generation fails.
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
        let projectManifest = try fileGenerator.generateFile(path: projectManifestPath,
                                                             in: groups.projectDescription,
                                                             sourceRootPath: sourceRootPath,
                                                             context: context)
        files.append(projectManifest.reference)

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
                                     buildConfigurationList: configurationListReference,
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
    ///   - pbxproj: PBXProj instance from the generated Xcode project.
    ///   - pbxProject: PBXProject instance from the generated project.
    ///   - groups: Project groups.
    ///   - sourceRootPath: Path to the folder that contains the project that is getting generated.
    ///   - context: generation context.
    /// - Throws: an error if the generation fails.
    func generateTarget(target: Target,
                        pbxproj: PBXProj,
                        pbxProject: PBXProject,
                        groups: ProjectGroups,
                        sourceRootPath _: AbsolutePath,
                        context _: GeneratorContexting) throws {
        /// Names
        let name = target.name
        let productName = "\(target.name).\(target.product.xcodeValue.fileExtension!)"

        /// Products reference.
        let productFileReference = PBXFileReference(sourceTree: .buildProductsDir, name: productName)
        let productFileReferenceRef = pbxproj.objects.addObject(productFileReference)
        groups.products.children.append(productFileReferenceRef)

        /// Target
        let target = PBXNativeTarget(name: target.name,
                                     buildConfigurationList: nil,
                                     buildPhases: [],
                                     buildRules: [],
                                     dependencies: [],
                                     productName: productName,
                                     productReference: productFileReferenceRef,
                                     productType: target.product.xcodeValue)
        let targetReference = pbxproj.objects.addObject(target)
        pbxProject.targets.append(targetReference)
    }
}
