import Foundation
@testable import ProjectDescription

extension Config {
    public static func test(generationOptions: [Config.GenerationOptions] = []) -> Config {
        Config(generationOptions: generationOptions)
    }
}

extension Template {
    public static func test(description: String = "Template",
                            attributes: [Template.Attribute] = [],
                            files: [Template.File] = []) -> Template
    {
        Template(description: description,
                 attributes: attributes,
                 files: files)
    }
}

extension Workspace {
    public static func test(name: String = "Workspace",
                            projects: [Path] = [],
                            additionalFiles: [FileElement] = []) -> Workspace
    {
        Workspace(name: name,
                  projects: projects,
                  additionalFiles: additionalFiles)
    }
}

extension Project {
    public static func test(name: String = "Project",
                            organizationName: String? = nil,
                            settings: Settings? = nil,
                            targets: [Target] = [],
                            additionalFiles: [FileElement] = []) -> Project
    {
        Project(name: name,
                organizationName: organizationName,
                settings: settings,
                targets: targets,
                additionalFiles: additionalFiles)
    }
}

extension Target {
    public static func test(name: String = "Target",
                            platform: Platform = .iOS,
                            product: Product = .framework,
                            productName: String? = nil,
                            bundleId: String = "com.some.bundle.id",
                            infoPlist: InfoPlist = .file(path: "Info.plist"),
                            sources: SourceFilesList = "Sources/**",
                            resources: [FileElement] = "Resources/**",
                            headers: Headers? = nil,
                            entitlements: Path? = Path("app.entitlements"),
                            actions: [TargetAction] = [],
                            dependencies: [TargetDependency] = [],
                            settings: Settings? = nil,
                            coreDataModels: [CoreDataModel] = [],
                            environment: [String: String] = [:]) -> Target
    {
        Target(name: name,
               platform: platform,
               product: product,
               productName: productName,
               bundleId: bundleId,
               infoPlist: infoPlist,
               sources: sources,
               resources: resources,
               headers: headers,
               entitlements: entitlements,
               actions: actions,
               dependencies: dependencies,
               settings: settings,
               coreDataModels: coreDataModels,
               environment: environment)
    }
}

extension TargetAction {
    public static func test(name: String = "Action",
                            tool: String? = nil,
                            path: Path? = nil,
                            order: Order = .pre,
                            arguments: [String] = []) -> TargetAction
    {
        TargetAction(name: name,
                     tool: tool,
                     path: path,
                     order: order,
                     arguments: arguments)
    }
}

extension Scheme {
    public static func test(name: String = "Scheme",
                            shared: Bool = false,
                            buildAction: BuildAction? = nil,
                            testAction: TestAction? = nil,
                            runAction: RunAction? = nil) -> Scheme
    {
        Scheme(name: name,
               shared: shared,
               buildAction: buildAction,
               testAction: testAction,
               runAction: runAction)
    }
}

extension BuildAction {
    public static func test(targets: [TargetReference] = []) -> BuildAction {
        BuildAction(targets: targets,
                    preActions: [ExecutionAction.test()],
                    postActions: [ExecutionAction.test()])
    }
}

extension TestAction {
    public static func test(targets: [TestableTarget] = [],
                            arguments: Arguments? = nil,
                            config: PresetBuildConfiguration = .debug,
                            coverage: Bool = true) -> TestAction
    {
        TestAction(targets: targets,
                   arguments: arguments,
                   config: config,
                   coverage: coverage,
                   preActions: [ExecutionAction.test()],
                   postActions: [ExecutionAction.test()])
    }
}

extension RunAction {
    public static func test(config: PresetBuildConfiguration = .debug,
                            executable: TargetReference? = nil,
                            arguments: Arguments? = nil) -> RunAction
    {
        RunAction(config: config,
                  executable: executable,
                  arguments: arguments)
    }
}

extension ExecutionAction {
    public static func test(title: String = "Test Script",
                            scriptText: String = "echo Test",
                            target: TargetReference? = TargetReference(projectPath: nil, target: "Target")) -> ExecutionAction
    {
        ExecutionAction(title: title,
                        scriptText: scriptText,
                        target: target)
    }
}

extension Arguments {
    public static func test(environment: [String: String] = [:],
                            launchArguments: [String: Bool] = [:]) -> Arguments
    {
        Arguments(environment: environment,
                  launchArguments: launchArguments)
    }
}

extension Dependencies {
    public static func test(name: String = "Any Dependency",
                            requirement: Dependency.Requirement = .exact("1.4.0")) -> Dependencies
    {
        Dependencies([.carthage(name: name, requirement: requirement)])
    }
}
