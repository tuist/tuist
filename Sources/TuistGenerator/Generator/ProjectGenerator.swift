import Basic
import Foundation
import SPMUtility
import TuistCore
import XcodeProj

struct ProjectConstants {
    var objectVersion: UInt
    var archiveVersion: UInt
}

extension ProjectConstants {
    static var xcode10: ProjectConstants {
        return ProjectConstants(objectVersion: 50,
                                archiveVersion: Xcode.LastKnown.archiveVersion)
    }

    static var xcode11: ProjectConstants {
        return ProjectConstants(objectVersion: 52,
                                archiveVersion: Xcode.LastKnown.archiveVersion)
    }
}

protocol ProjectGenerating: AnyObject {
    func generate(project: Project,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath?) throws -> GeneratedProject
}

final class ProjectGenerator: ProjectGenerating {
    // MARK: - Attributes

    /// Generator for the project targets.
    let targetGenerator: TargetGenerating

    /// Generator for the project configuration.
    let configGenerator: ConfigGenerating

    /// Generator for the project schemes.
    let schemesGenerator: SchemesGenerating

    /// Generator for the project derived files.
    let derivedFileGenerator: DerivedFileGenerating

    // MARK: - Init

    /// Initializes the project generator with its attributes.
    ///
    /// - Parameters:
    ///   - targetGenerator: Generator for the project targets.
    ///   - configGenerator: Generator for the project configuration.
    ///   - schemesGenerator: Generator for the project schemes.
    ///   - derivedFileGenerator: Generator for the project derived files.
    init(targetGenerator: TargetGenerating = TargetGenerator(),
         configGenerator: ConfigGenerating = ConfigGenerator(),
         schemesGenerator: SchemesGenerating = SchemesGenerator(),
         derivedFileGenerator: DerivedFileGenerating = DerivedFileGenerator()) {
        self.targetGenerator = targetGenerator
        self.configGenerator = configGenerator
        self.schemesGenerator = schemesGenerator
        self.derivedFileGenerator = derivedFileGenerator
    }

    // MARK: - ProjectGenerating

    func generate(project: Project,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath? = nil) throws -> GeneratedProject {
        Printer.shared.print("Generating project \(project.name)")

        // Getting the path.
        let sourceRootPath = sourceRootPath ?? project.path

        let xcodeprojPath = sourceRootPath.appending(component: "\(project.fileName).xcodeproj")

        // Project and workspace.
        return try generateProjectAndWorkspace(project: project,
                                               graph: graph,
                                               sourceRootPath: sourceRootPath,
                                               xcodeprojPath: xcodeprojPath)
    }

    // MARK: - Fileprivate

    private func generateProjectAndWorkspace(project: Project,
                                             graph: Graphing,
                                             sourceRootPath: AbsolutePath,
                                             xcodeprojPath: AbsolutePath) throws -> GeneratedProject {
        // Derived files
        let deleteOldDerivedFiles = try derivedFileGenerator.generate(project: project, sourceRootPath: sourceRootPath)

        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        let projectConstants = try determineProjectConstants()
        let pbxproj = PBXProj(objectVersion: projectConstants.objectVersion,
                              archiveVersion: projectConstants.archiveVersion,
                              classes: [:])
        let groups = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: sourceRootPath)
        let fileElements = ProjectFileElements()
        try fileElements.generateProjectFiles(project: project,
                                              graph: graph,
                                              groups: groups,
                                              pbxproj: pbxproj,
                                              sourceRootPath: sourceRootPath)
        let configurationList = try configGenerator.generateProjectConfig(project: project,
                                                                          pbxproj: pbxproj,
                                                                          fileElements: fileElements)
        let pbxProject = try generatePbxproject(project: project,
                                                configurationList: configurationList,
                                                groups: groups,
                                                pbxproj: pbxproj)

        let nativeTargets = try generateTargets(project: project,
                                                pbxproj: pbxproj,
                                                pbxProject: pbxProject,
                                                groups: groups,
                                                fileElements: fileElements,
                                                sourceRootPath: sourceRootPath,
                                                graph: graph)

        generateTestTargetIdentity(project: project,
                                   pbxproj: pbxproj,
                                   pbxProject: pbxProject)

        try deleteOldDerivedFiles()

        return try write(xcodeprojPath: xcodeprojPath,
                         nativeTargets: nativeTargets,
                         workspace: workspace,
                         pbxproj: pbxproj,
                         project: project,
                         graph: graph)
    }

    private func generatePbxproject(project: Project,
                                    configurationList: XCConfigurationList,
                                    groups: ProjectGroups,
                                    pbxproj: PBXProj) throws -> PBXProject {
        let pbxProject = PBXProject(name: project.name,
                                    buildConfigurationList: configurationList,
                                    compatibilityVersion: Xcode.Default.compatibilityVersion,
                                    mainGroup: groups.main,
                                    developmentRegion: Xcode.Default.developmentRegion,
                                    hasScannedForEncodings: 0,
                                    knownRegions: ["en"],
                                    productsGroup: groups.products,
                                    projectDirPath: "",
                                    projects: [],
                                    projectRoots: [],
                                    targets: [])

        pbxproj.add(object: pbxProject)
        pbxproj.rootObject = pbxProject
        return pbxProject
    }

    private func generateTargets(project: Project,
                                 pbxproj: PBXProj,
                                 pbxProject: PBXProject,
                                 groups _: ProjectGroups,
                                 fileElements: ProjectFileElements,
                                 sourceRootPath: AbsolutePath,
                                 graph: Graphing) throws -> [String: PBXNativeTarget] {
        var nativeTargets: [String: PBXNativeTarget] = [:]
        try project.targets.forEach { target in
            let nativeTarget = try targetGenerator.generateTarget(target: target,
                                                                  pbxproj: pbxproj,
                                                                  pbxProject: pbxProject,
                                                                  projectSettings: project.settings,
                                                                  fileElements: fileElements,
                                                                  path: project.path,
                                                                  sourceRootPath: sourceRootPath,
                                                                  graph: graph)
            nativeTargets[target.name] = nativeTarget
        }

        /// Target dependencies
        try targetGenerator.generateTargetDependencies(path: project.path,
                                                       targets: project.targets,
                                                       nativeTargets: nativeTargets,
                                                       graph: graph)
        return nativeTargets
    }

    private func generateTestTargetIdentity(project _: Project,
                                            pbxproj: PBXProj,
                                            pbxProject: PBXProject) {
        func testTargetName(_ target: PBXTarget) -> String? {
            guard let buildConfigurations = target.buildConfigurationList?.buildConfigurations else {
                return nil
            }

            return buildConfigurations
                .compactMap { $0.buildSettings["TEST_TARGET_NAME"] as? String }
                .first
        }

        let testTargets = pbxproj.nativeTargets.filter { $0.productType == .uiTestBundle || $0.productType == .unitTestBundle }

        for testTarget in testTargets {
            guard let name = testTargetName(testTarget) else {
                continue
            }

            guard let target = pbxproj.targets(named: name).first else {
                continue
            }

            var attributes = pbxProject.targetAttributes[testTarget] ?? [:]

            attributes["TestTargetID"] = target

            pbxProject.setTargetAttributes(attributes, target: testTarget)
        }
    }

    private func write(xcodeprojPath: AbsolutePath,
                       nativeTargets: [String: PBXNativeTarget],
                       workspace: XCWorkspace,
                       pbxproj: PBXProj,
                       project: Project,
                       graph _: Graphing) throws -> GeneratedProject {
        var generatedProject: GeneratedProject!

        try FileHandler.shared.inTemporaryDirectory { temporaryPath in

            try writeXcodeproj(workspace: workspace,
                               pbxproj: pbxproj,
                               xcodeprojPath: temporaryPath)
            generatedProject = GeneratedProject(pbxproj: pbxproj,
                                                path: temporaryPath,
                                                targets: nativeTargets,
                                                name: xcodeprojPath.components.last!)
            try writeSchemes(project: project,
                             generatedProject: generatedProject)
            try FileHandler.shared.replace(xcodeprojPath, with: temporaryPath)
        }

        return try generatedProject.at(path: xcodeprojPath)
    }

    private func writeXcodeproj(workspace: XCWorkspace,
                                pbxproj: PBXProj,
                                xcodeprojPath: AbsolutePath) throws {
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
        try xcodeproj.write(path: xcodeprojPath.path)
    }

    private func writeSchemes(project: Project,
                              generatedProject: GeneratedProject) throws {
        try schemesGenerator.generateTargetSchemes(project: project,
                                                   generatedProject: generatedProject)
    }

    private func determineProjectConstants() throws -> ProjectConstants {
        let version = try XcodeController.shared.selectedVersion()

        if version.major >= 11 {
            return .xcode11
        } else {
            return .xcode10
        }
    }
}
