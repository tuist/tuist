import Basic
import Foundation
import xcodeproj

protocol TargetGenerating: AnyObject {
    func generateManifestsTarget(project: Project,
                                 pbxproj: PBXProj,
                                 pbxProject: PBXProject,
                                 mainGroup: PBXGroup,
                                 productsGroup: PBXGroup,
                                 sourceRootPath: AbsolutePath,
                                 context: GeneratorContexting) throws
}

final class TargetGenerator: TargetGenerating {
    /// Config generator.
    let configGenerator: ConfigGenerating

    /// File generator.
    let fileGenerator: FileGenerating

    init(configGenerator: ConfigGenerating = ConfigGenerator(),
         fileGenerator: FileGenerating = FileGenerator()) {
        self.configGenerator = configGenerator
        self.fileGenerator = fileGenerator
    }

    func generateManifestsTarget(project: Project,
                                 pbxproj: PBXProj,
                                 pbxProject: PBXProject,
                                 mainGroup: PBXGroup,
                                 productsGroup: PBXGroup,
                                 sourceRootPath: AbsolutePath,
                                 context: GeneratorContexting) throws {
        /// Names
        let name = "\(project.name)Description"
        let frameworkName = "\(name).framework"

        /// Products reference.
        let productFileReference = PBXFileReference(sourceTree: .buildProductsDir, name: frameworkName)
        let productFileReferenceRef = pbxproj.objects.addObject(productFileReference)
        productsGroup.children.append(productFileReferenceRef)

        /// Group
        let group = PBXGroup(sourceTree: .group, name: name)
        let groupReference = pbxproj.objects.addObject(group)
        mainGroup.children.insert(groupReference, at: 0)

        /// Files
        var files: [PBXObjectReference] = []
        let projectManifestPath = project.path.appending(component: Constants.Manifest.project)
        let projectManifest = try fileGenerator.generateFile(path: projectManifestPath, in: group, sourceRootPath: sourceRootPath, context: context)
        files.append(projectManifest.reference)
        if let config = project.config {
            let configManifestPath = config.path.appending(component: Constants.Manifest.config)
            let configManifest = try fileGenerator.generateFile(path: configManifestPath, in: group, sourceRootPath: sourceRootPath, context: context)
            files.append(configManifest.reference)
        }

        // Configuration
        let configurationList = XCConfigurationList(buildConfigurations: [])
        let debugConfig = XCBuildConfiguration(name: "Debug")
        let debugConfigReference = pbxproj.objects.addObject(debugConfig)
        debugConfig.buildSettings = BuildSettingsProvider.targetDefault(variant: .debug, platform: .macOS, product: .framework, swift: true)
        let releaseConfig = XCBuildConfiguration(name: "Release")
        let releaseConfigReference = pbxproj.objects.addObject(releaseConfig)
        releaseConfig.buildSettings = BuildSettingsProvider.targetDefault(variant: .release, platform: .macOS, product: .framework, swift: true)
        configurationList.buildConfigurations.append(debugConfigReference)
        configurationList.buildConfigurations.append(releaseConfigReference)
        let configurationListReference = pbxproj.objects.addObject(configurationList)

        func addSettings(configuration: XCBuildConfiguration) throws {
            let frameworkParentDirectory = try context.resourceLocator.projectDescription().parentDirectory
            configuration.buildSettings["FRAMEWORK_SEARCH_PATHS"] = frameworkParentDirectory.asString
            configuration.buildSettings["SWIFT_VERSION"] = Constants.swiftVersion
        }
        try addSettings(configuration: debugConfig)
        try addSettings(configuration: releaseConfig)

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
}
