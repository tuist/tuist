import Foundation
import Path
import TuistCore
import TuistCoreTesting
import TuistLoaderTesting
import XcodeGraph
@testable import TuistGenerator
@testable import TuistSupport
@testable import TuistSupportTesting

final class TestModelGenerator {
    struct WorkspaceConfig {
        var projects: Int = 50
        var testTargets: Int = 3
        var frameworkTargets: Int = 3
        var staticFrameworkTargets: Int = 3
        var staticLibraryTargets: Int = 3
        var schemes: Int = 10
        var sources: Int = 100
        var resources: Int = 100
        var headers: Int = 100
    }

    private let rootPath: AbsolutePath
    private let config: WorkspaceConfig

    init(rootPath: AbsolutePath, config: WorkspaceConfig) {
        self.rootPath = rootPath
        self.config = config
    }

    func generate() throws -> Graph {
        let models = try createModels()
        let graphLoader = GraphLoader(
            frameworkMetadataProvider: MockFrameworkMetadataProvider(),
            libraryMetadataProvider: MockLibraryMetadataProvider(),
            xcframeworkMetadataProvider: MockXCFrameworkMetadataProvider(),
            systemFrameworkMetadataProvider: SystemFrameworkMetadataProvider()
        )

        return try graphLoader.loadWorkspace(
            workspace: models.workspace,
            projects: models.projects
        )
    }

    private func createModels() throws -> WorkspaceWithProjects {
        let projects = try (0 ..< config.projects).map {
            try createProjectWithDependencies(name: "App\($0)")
        }
        let workspace = try createWorkspace(path: rootPath, projects: projects.map(\.name))
        return WorkspaceWithProjects(workspace: workspace, projects: projects)
    }

    private func createProjectWithDependencies(name: String) throws -> Project {
        let frameworksNames = (0 ..< config.frameworkTargets).map {
            "\(name)Framework\($0)"
        }
        let staticFrameworkNames = (0 ..< config.staticFrameworkTargets).map {
            "\(name)StaticFramework\($0)"
        }
        let staticLibraryNames = (0 ..< config.staticLibraryTargets).map {
            "\(name)Library\($0)"
        }
        let unitTestsTargetNames = (0 ..< config.testTargets).map { "\(name)TestAppTests\($0)" }
        let targetSettings = Settings(
            base: [
                "A1": "A_VALUE",
                "B1": "B_VALUE",
                "C1": "C_VALUE",
            ],
            configurations: [
                .debug: nil,
                .release: nil,
                .debug("CustomDebug"): nil,
                .release("CustomRelease"): nil,
            ]
        )
        let projectSettings = Settings(
            base: [
                "A2": "A_VALUE",
                "B2": "B_VALUE",
                "C2": "C_VALUE",
            ],
            configurations: [
                .debug: nil,
                .release: nil,
                .debug("CustomDebug2"): nil,
                .release("CustomRelease2"): nil,
            ]
        )
        let projectPath = try pathTo(name)
        let dependencies = try createDependencies(relativeTo: projectPath)
        let frameworkTargets = try frameworksNames.map {
            try createTarget(name: $0, product: .framework, dependencies: dependencies)
        }
        let staticFrameworkTargets = try staticFrameworkNames.map {
            try createTarget(name: $0, product: .staticFramework)
        }
        let staticLibraryTargets = try staticLibraryNames.map {
            try createTarget(name: $0, product: .staticLibrary)
        }
        let appTarget = try createTarget(
            path: projectPath,
            name: "\(name)AppTarget",
            settings: targetSettings,
            dependencies: frameworksNames + staticFrameworkNames + staticLibraryNames
        )
        let appUnitTestsTargets = try unitTestsTargetNames.map { try createTarget(
            path: projectPath,
            name: $0,
            product: .unitTests,
            settings: nil,
            dependencies: [appTarget.name]
        ) }
        let schemes = try createSchemes(
            projectName: name,
            appTarget: appTarget,
            otherTargets: frameworkTargets + staticLibraryTargets + staticLibraryTargets
        )
        let project = try createProject(
            path: projectPath,
            name: name,
            settings: projectSettings,
            targets: [appTarget] + frameworkTargets + staticFrameworkTargets + staticLibraryTargets + appUnitTestsTargets,
            schemes: schemes
        )

        return project
    }

    private func createWorkspace(path: AbsolutePath, projects: [String]) throws -> Workspace {
        Workspace(
            path: path,
            xcWorkspacePath: path.appending(component: "Workspace.xcworkspace"),
            name: "Workspace",
            projects: try projects.map { try pathTo($0) }
        )
    }

    private func createProject(
        path: AbsolutePath,
        name: String,
        settings: Settings,
        targets: [Target],
        packages: [Package] = [],
        schemes: [Scheme]
    ) throws -> Project {
        Project(
            path: path,
            sourceRootPath: path,
            xcodeProjPath: path.appending(component: "App.xcodeproj"),
            name: name,
            organizationName: nil,
            classPrefix: nil,
            defaultKnownRegions: nil,
            developmentRegion: nil,
            options: .test(),
            settings: settings,
            filesGroup: .group(name: "Project"),
            targets: targets,
            packages: packages,
            schemes: schemes,
            ideTemplateMacros: nil,
            additionalFiles: try createAdditionalFiles(path: path),
            resourceSynthesizers: [],
            lastUpgradeCheck: nil,
            isExternal: false
        )
    }

    private func createTarget(
        path: AbsolutePath,
        name: String,
        product: Product = .app,
        settings: Settings?,
        dependencies: [String]
    ) throws -> Target {
        Target(
            name: name,
            destinations: .iOS,
            product: product,
            productName: name,
            bundleId: "test.bundle",
            settings: settings,
            sources: try createSources(path: path),
            resources: try createResources(path: path),
            headers: try createHeaders(path: path),
            filesGroup: .group(name: "ProjectGroup"),
            dependencies: dependencies.map { TargetDependency.target(name: $0) }
        )
    }

    private func createSources(path: AbsolutePath) throws -> [SourceFile] {
        let sources: [SourceFile] = try (0 ..< config.sources)
            .map { "Sources/SourceFile\($0).swift" }
            .map { SourceFile(path: path.appending(try RelativePath(validating: $0))) }
            .shuffled()
        return sources
    }

    private func createHeaders(path: AbsolutePath) throws -> Headers {
        let publicHeaders = try (0 ..< config.headers)
            .map { "Sources/PublicHeader\($0).h" }
            .map { path.appending(try RelativePath(validating: $0)) }
            .shuffled()

        let privateHeaders = try (0 ..< config.headers)
            .map { "Sources/PrivateHeader\($0).h" }
            .map { path.appending(try RelativePath(validating: $0)) }
            .shuffled()

        let projectHeaders = try (0 ..< config.headers)
            .map { "Sources/ProjectHeader\($0).h" }
            .map { path.appending(try RelativePath(validating: $0)) }
            .shuffled()

        return Headers(public: publicHeaders, private: privateHeaders, project: projectHeaders)
    }

    private func createResources(path: AbsolutePath) throws -> ResourceFileElements {
        let files = try (0 ..< config.resources)
            .map { "Resources/Resource\($0).png" }
            .map { ResourceFileElement.file(path: path.appending(try RelativePath(validating: $0))) }

        let folderReferences = try (0 ..< 10)
            .map { "Resources/Folder\($0)" }
            .map { ResourceFileElement.folderReference(path: path.appending(try RelativePath(validating: $0))) }

        return ResourceFileElements((files + folderReferences).shuffled())
    }

    private func createAdditionalFiles(path: AbsolutePath) throws -> [FileElement] {
        let files = try (0 ..< 10)
            .map { "Files/File\($0).md" }
            .map { FileElement.file(path: path.appending(try RelativePath(validating: $0))) }

        // When using ** glob patterns (e.g. `Documentation/**`)
        // the results will include the folders in addition to the files
        //
        // e.g.
        //    Documentation
        //    Documentation/a.md
        //    Documentation/Subfolder
        //    Documentation/Subfolder/a.md
        let filesWithFolderPaths = files + [
            .file(path: path.appending(try RelativePath(validating: "Files"))),
        ]

        let folderReferences = try (0 ..< 10)
            .map { "Documentation\($0)" }
            .map { FileElement.folderReference(path: path.appending(try RelativePath(validating: $0))) }

        return (filesWithFolderPaths + folderReferences).shuffled()
    }

    private func createTarget(
        name: String,
        product: Product,
        dependencies: [TargetDependency] = []
    ) throws -> Target {
        Target(
            name: name,
            destinations: [.iPhone, .iPad, .mac],
            product: product,
            productName: nil,
            bundleId: "test.bundle.\(name)",
            settings: nil,
            sources: [],
            filesGroup: .group(name: "ProjectGroup"),
            dependencies: dependencies
        )
    }

    private func createDependencies(relativeTo path: AbsolutePath) throws -> [TargetDependency] {
        let frameworks = try (0 ..< 10)
            .map { "Frameworks/Framework\($0).framework" }
            .map { TargetDependency.framework(path: path.appending(try RelativePath(validating: $0)), status: .required) }

        let libraries = try createLibraries(relativeTo: path)
        let sdks: [TargetDependency] = [
            .sdk(name: "Accelerate.framework", status: .required),
            .sdk(name: "AVKit.framework", status: .required),
            .sdk(name: "Intents.framework", status: .optional),
            .sdk(name: "HealthKit.framework", status: .optional),
            .sdk(name: "libc++.tbd", status: .required),
            .sdk(name: "libxml2.tbd", status: .required),
        ]
        return (frameworks + libraries + sdks).shuffled()
    }

    private func createLibraries(relativeTo path: AbsolutePath) throws -> [TargetDependency] {
        var libraries = [TargetDependency]()

        for i in 0 ..< 10 {
            let libraryName = "Library\(i)"
            let library = "Libraries/\(libraryName)/lib\(libraryName).a"
            let headers = "Libraries/\(libraryName)/Headers"
            let swiftModuleMap = "Libraries/\(libraryName)/\(libraryName).swiftmodule"

            libraries.append(
                .library(
                    path: path.appending(try RelativePath(validating: library)),
                    publicHeaders: path.appending(try RelativePath(validating: headers)),
                    swiftModuleMap: path.appending(try RelativePath(validating: swiftModuleMap))
                )
            )
        }

        return libraries
    }

    private func createSchemes(projectName: String, appTarget: Target, otherTargets: [Target]) throws -> [Scheme] {
        let targets = try ([appTarget] + otherTargets).map { try targetReference(from: $0, projectName: projectName) }
        return (0 ..< config.schemes).map {
            let boolStub = $0 % 2 == 0

            return Scheme(
                name: "Scheme \($0)",
                shared: boolStub,
                buildAction: BuildAction(
                    targets: targets,
                    preActions: createExecutionActions(),
                    postActions: createExecutionActions()
                ),
                testAction: TestAction(
                    targets: targets.map { TestableTarget(target: $0) },
                    arguments: createArguments(),
                    configurationName: "Debug",
                    attachDebugger: true,
                    coverage: boolStub,
                    codeCoverageTargets: targets,
                    expandVariableFromTarget: nil,
                    preActions: createExecutionActions(),
                    postActions: createExecutionActions(),
                    diagnosticsOptions: SchemeDiagnosticsOptions()
                ),
                runAction: RunAction(
                    configurationName: "Debug",
                    attachDebugger: true,
                    customLLDBInitFile: nil,
                    executable: nil,
                    filePath: nil,
                    arguments: createArguments(),
                    diagnosticsOptions: SchemeDiagnosticsOptions()
                ),
                archiveAction: ArchiveAction(
                    configurationName: "Debug",
                    revealArchiveInOrganizer: boolStub,
                    preActions: createExecutionActions(),
                    postActions: createExecutionActions()
                )
            )
        }
    }

    private func createArguments() -> Arguments {
        let environmentVariables = (0 ..< 10).reduce([String: EnvironmentVariable]()) { acc, value in
            var acc = acc
            let arg = EnvironmentVariable(value: "EnvironmentValue\(value)", isEnabled: true)
            acc["Environment\(value)"] = arg
            return acc
        }
        let launch = (0 ..< 10).reduce([LaunchArgument]()) { acc, value in
            var acc = acc
            let arg = LaunchArgument(name: "Launch\(value)", isEnabled: value % 2 == 0)
            acc.append(arg)
            return acc
        }
        return Arguments(environmentVariables: environmentVariables, launchArguments: launch)
    }

    private func createExecutionActions() -> [ExecutionAction] {
        (0 ..< 10).map {
            ExecutionAction(
                title: "ExecutionAction\($0)",
                scriptText: "ScripText\($0)",
                target: nil,
                shellPath: nil,
                showEnvVarsInLog: false
            )
        }
    }

    private func pathTo(_ relativePath: String) throws -> AbsolutePath {
        rootPath.appending(try RelativePath(validating: relativePath))
    }

    private func targetReference(from target: Target, projectName: String) throws -> TargetReference {
        TargetReference(projectPath: try pathTo(projectName), name: target.name)
    }
}
