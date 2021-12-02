import Foundation
@testable import ProjectDescription

public extension Config {
    static func test(generationOptions: [Config.GenerationOptions] = [],
                     plugins: [PluginLocation] = []) -> Config
    {
        Config(plugins: plugins, generationOptions: generationOptions)
    }
}

public extension Template {
    static func test(description: String = "Template",
                     attributes: [Attribute] = [],
                     items: [Template.Item] = []) -> Template
    {
        Template(
            description: description,
            attributes: attributes,
            items: items
        )
    }
}

public extension Workspace {
    static func test(name: String = "Workspace",
                     projects: [Path] = [],
                     additionalFiles: [FileElement] = []) -> Workspace
    {
        Workspace(
            name: name,
            projects: projects,
            additionalFiles: additionalFiles
        )
    }
}

public extension Project {
    static func test(name: String = "Project",
                     organizationName: String? = nil,
                     settings: Settings? = nil,
                     targets: [Target] = [],
                     additionalFiles: [FileElement] = []) -> Project
    {
        Project(
            name: name,
            organizationName: organizationName,
            settings: settings,
            targets: targets,
            additionalFiles: additionalFiles
        )
    }
}

public extension Target {
    static func test(name: String = "Target",
                     platform: Platform = .iOS,
                     product: Product = .framework,
                     productName: String? = nil,
                     bundleId: String = "com.some.bundle.id",
                     infoPlist: InfoPlist = .file(path: "Info.plist"),
                     sources: SourceFilesList = "Sources/**",
                     resources: ResourceFileElements = "Resources/**",
                     headers: Headers? = nil,
                     entitlements: Path? = Path("app.entitlements"),
                     scripts: [TargetScript] = [],
                     dependencies: [TargetDependency] = [],
                     settings: Settings? = nil,
                     coreDataModels: [CoreDataModel] = [],
                     environment: [String: String] = [:]) -> Target
    {
        Target(
            name: name,
            platform: platform,
            product: product,
            productName: productName,
            bundleId: bundleId,
            infoPlist: infoPlist,
            sources: sources,
            resources: resources,
            headers: headers,
            entitlements: entitlements,
            scripts: scripts,
            dependencies: dependencies,
            settings: settings,
            coreDataModels: coreDataModels,
            environment: environment
        )
    }
}

public extension TargetScript {
    static func test(name: String = "Action",
                     tool: String = "",
                     order: Order = .pre,
                     arguments: [String] = [],
                     inputPaths: [Path] = [],
                     inputFileListPaths: [Path] = [],
                     outputPaths: [Path] = [],
                     outputFileListPaths: [Path] = []) -> TargetScript
    {
        TargetScript(
            name: name,
            script: .tool(tool, arguments),
            order: order,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths
        )
    }
}

public extension Scheme {
    static func test(name: String = "Scheme",
                     shared: Bool = false,
                     buildAction: BuildAction? = nil,
                     testAction: TestAction? = nil,
                     runAction: RunAction? = nil) -> Scheme
    {
        Scheme(
            name: name,
            shared: shared,
            buildAction: buildAction,
            testAction: testAction,
            runAction: runAction
        )
    }
}

public extension BuildAction {
    static func test(targets: [TargetReference] = []) -> BuildAction {
        BuildAction(
            targets: targets,
            preActions: [ExecutionAction.test()],
            postActions: [ExecutionAction.test()]
        )
    }
}

public extension TestAction {
    static func test(targets: [TestableTarget] = [],
                     arguments: Arguments? = nil,
                     configuration: ConfigurationName = .debug,
                     coverage: Bool = true) -> TestAction
    {
        TestAction.targets(
            targets,
            arguments: arguments,
            configuration: configuration,
            preActions: [ExecutionAction.test()],
            postActions: [ExecutionAction.test()],
            options: .options(coverage: coverage)
        )
    }
}

public extension RunAction {
    static func test(configuration: ConfigurationName = .debug,
                     executable: TargetReference? = nil,
                     arguments: Arguments? = nil) -> RunAction
    {
        RunAction(
            configuration: configuration,
            executable: executable,
            arguments: arguments
        )
    }
}

public extension ExecutionAction {
    static func test(title: String = "Test Script",
                     scriptText: String = "echo Test",
                     target: TargetReference? = TargetReference(projectPath: nil, target: "Target")) -> ExecutionAction
    {
        ExecutionAction(
            title: title,
            scriptText: scriptText,
            target: target
        )
    }
}

public extension Arguments {
    static func test(environment: [String: String] = [:],
                     launchArguments: [LaunchArgument] = []) -> Arguments
    {
        Arguments(
            environment: environment,
            launchArguments: launchArguments
        )
    }
}

public extension Dependencies {
    static func test(carthageDependencies: CarthageDependencies? = nil) -> Dependencies {
        Dependencies(carthage: carthageDependencies)
    }
}

public extension Plugin {
    static func test(name: String = "Plugin") -> Plugin {
        Plugin(name: name)
    }
}
