import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeProj

protocol TargetGenerating: AnyObject {
    func generateTarget(
        target: Target,
        project: Project,
        pbxproj: PBXProj,
        pbxProject: PBXProject,
        projectSettings: Settings,
        fileElements: ProjectFileElements,
        path: AbsolutePath,
        graphTraverser: GraphTraversing
    ) async throws -> PBXNativeTarget

    func generateTargetDependencies(
        path: AbsolutePath,
        targets: [Target],
        nativeTargets: [String: PBXNativeTarget],
        graphTraverser: GraphTraversing
    ) throws
}

final class TargetGenerator: TargetGenerating {
    // MARK: - Attributes

    let configGenerator: ConfigGenerating
    let buildPhaseGenerator: BuildPhaseGenerating
    let linkGenerator: LinkGenerating
    let buildRulesGenerator: BuildRulesGenerating

    // MARK: - Init

    init(
        configGenerator: ConfigGenerating = ConfigGenerator(),
        buildPhaseGenerator: BuildPhaseGenerating = BuildPhaseGenerator(),
        linkGenerator: LinkGenerating = LinkGenerator(),
        buildRulesGenerator: BuildRulesGenerating = BuildRulesGenerator()
    ) {
        self.configGenerator = configGenerator
        self.buildPhaseGenerator = buildPhaseGenerator
        self.linkGenerator = linkGenerator
        self.buildRulesGenerator = buildRulesGenerator
    }

    // MARK: - TargetGenerating

    // swiftlint:disable:next function_body_length
    func generateTarget(
        target: Target,
        project: Project,
        pbxproj: PBXProj,
        pbxProject: PBXProject,
        projectSettings: Settings,
        fileElements: ProjectFileElements,
        path: AbsolutePath,
        graphTraverser: GraphTraversing
    ) async throws -> PBXNativeTarget {
        Logger.current.debug("TargetGenerator: Starting generation for target \(target.name)")

        // Products reference.
        let productFileReference = fileElements.products[target.name]!

        // Target
        Logger.current.debug("TargetGenerator: Creating PBXNativeTarget for \(target.name)")
        let pbxTarget = PBXNativeTarget(
            name: target.name,
            buildConfigurationList: nil,
            buildPhases: [],
            buildRules: [],
            dependencies: [],
            productInstallPath: nil,
            productName: target.productName,
            product: productFileReference,
            productType: target.product.xcodeValue
        )
        pbxproj.add(object: pbxTarget)
        pbxProject.targets.append(pbxTarget)

        // Buildable folders
        Logger.current.debug("TargetGenerator: Generating synchronized groups for \(target.name)")
        generateSynchronizedGroups(target: target, fileElements: fileElements, pbxTarget: pbxTarget, pbxproj: pbxproj)

        // Pre actions
        Logger.current.debug("TargetGenerator: Generating pre-scripts for \(target.name)")
        try buildPhaseGenerator.generateScripts(
            target.scripts.preScripts,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            sourceRootPath: project.sourceRootPath
        )

        // Build configuration
        Logger.current.debug("TargetGenerator: Generating target config for \(target.name)")
        try await configGenerator.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: projectSettings,
            fileElements: fileElements,
            graphTraverser: graphTraverser,
            sourceRootPath: project.sourceRootPath
        )

        // Build phases
        Logger.current.debug("TargetGenerator: Generating build phases for \(target.name)")
        try await buildPhaseGenerator.generateBuildPhases(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Links
        Logger.current.debug("TargetGenerator: Generating links for \(target.name)")
        try linkGenerator.generateLinks(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements,
            path: path,
            sourceRootPath: project.sourceRootPath,
            graphTraverser: graphTraverser
        )

        // Post actions
        Logger.current.debug("TargetGenerator: Generating post-scripts for \(target.name)")
        try buildPhaseGenerator.generateScripts(
            target.scripts.postScripts,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            sourceRootPath: project.sourceRootPath
        )

        Logger.current.debug("TargetGenerator: Generating build rules for \(target.name)")
        try buildRulesGenerator.generateBuildRules(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj
        )

        Logger.current.debug("TargetGenerator: Finished generation for target \(target.name)")
        return pbxTarget
    }

    private func generateSynchronizedGroups(
        target: Target,
        fileElements: ProjectFileElements,
        pbxTarget: PBXNativeTarget,
        pbxproj: PBXProj
    ) {
        for buildableFolder in target.buildableFolders {
            guard let fileElement = fileElements.elements[buildableFolder.path],
                  let synchronizedGroup = fileElement as? PBXFileSystemSynchronizedRootGroup else { continue }
            if pbxTarget.fileSystemSynchronizedGroups == nil {
                pbxTarget.fileSystemSynchronizedGroups = []
            }
            pbxTarget.fileSystemSynchronizedGroups?.append(synchronizedGroup)

            for exception in buildableFolder.exceptions {
                let membershipExceptions = exception.excluded.compactMap {
                    $0.isDescendant(of: buildableFolder.path) ? $0.relative(to: buildableFolder.path).pathString : nil
                }
                let additionalCompilerFlagsByRelativePath = Dictionary(uniqueKeysWithValues: exception.compilerFlags
                    .compactMap { path, compilerFlags -> (
                        String,
                        String
                    )? in
                        guard path.isDescendant(of: buildableFolder.path) else { return nil }
                        return (path.relative(to: buildableFolder.path).pathString, compilerFlags)
                    }
                )

                let exceptionSet = PBXFileSystemSynchronizedBuildFileExceptionSet(
                    target: pbxTarget,
                    membershipExceptions: membershipExceptions,
                    publicHeaders: exception.publicHeaders.map { $0.relative(to: buildableFolder.path).pathString },
                    privateHeaders: exception.privateHeaders.map { $0.relative(to: buildableFolder.path).pathString },
                    additionalCompilerFlagsByRelativePath: additionalCompilerFlagsByRelativePath,
                    attributesByRelativePath: nil
                )
                pbxproj.add(object: exceptionSet)
                synchronizedGroup.exceptions?.append(exceptionSet)
            }
        }
    }

    func generateTargetDependencies(
        path: AbsolutePath,
        targets: [Target],
        nativeTargets: [String: PBXNativeTarget],
        graphTraverser: GraphTraversing
    ) throws {
        Logger.current.debug("TargetGenerator: Generating dependencies for \(targets.count) targets")
        for targetSpec in targets {
            let dependenciesAndConditions = graphTraverser.directLocalTargetDependencies(
                path: path,
                name: targetSpec.name
            ).sorted()

            Logger.current.debug("TargetGenerator: Target \(targetSpec.name) has \(dependenciesAndConditions.count) dependencies")
            for dependency in dependenciesAndConditions {
                let nativeTarget = nativeTargets[targetSpec.name]!
                let nativeDependency = nativeTargets[dependency.target.name]!
                let pbxTargetDependency = try nativeTarget.addDependency(target: nativeDependency)
                pbxTargetDependency?.applyCondition(dependency.condition, applicableTo: targetSpec)
            }
        }
        Logger.current.debug("TargetGenerator: Finished generating target dependencies")
    }
}
