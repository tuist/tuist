import Foundation
@testable import ProjectDescription

extension Config {
    public static func test(
        generationOptions: Config.GenerationOptions = .options(),
        plugins: [PluginLocation] = []
    ) -> Config {
        Config(plugins: plugins, generationOptions: generationOptions)
    }
}

extension Template {
    public static func test(
        description: String = "Template",
        attributes: [Attribute] = [],
        items: [Template.Item] = []
    ) -> Template {
        Template(
            description: description,
            attributes: attributes,
            items: items
        )
    }
}

extension Workspace {
    public static func test(
        name: String = "Workspace",
        projects: [Path] = [],
        schemes: [Scheme] = [],
        additionalFiles: [FileElement] = []
    ) -> Workspace {
        Workspace(
            name: name,
            projects: projects,
            schemes: schemes,
            additionalFiles: additionalFiles
        )
    }
}

extension Project {
    public static func test(
        name: String = "Project",
        organizationName: String? = nil,
        settings: Settings? = nil,
        targets: [Target] = [],
        additionalFiles: [FileElement] = []
    ) -> Project {
        Project(
            name: name,
            organizationName: organizationName,
            settings: settings,
            targets: targets,
            additionalFiles: additionalFiles
        )
    }
}

extension Target {
    public static func test(
        name: String = "Target",
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
        environment: [String: String] = [:]
    ) -> Target {
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

extension TargetScript {
    public static func test(
        name: String = "Action",
        tool: String = "",
        order: Order = .pre,
        arguments: [String] = [],
        inputPaths: [Path] = [],
        inputFileListPaths: [Path] = [],
        outputPaths: [Path] = [],
        outputFileListPaths: [Path] = [],
        dependencyFile: Path? = nil
    ) -> TargetScript {
        TargetScript(
            name: name,
            script: .tool(path: tool, args: arguments),
            order: order,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            dependencyFile: dependencyFile
        )
    }
}

extension Scheme {
    public static func test(
        name: String = "Scheme",
        shared: Bool = false,
        buildAction: BuildAction? = nil,
        testAction: TestAction? = nil,
        runAction: RunAction? = nil
    ) -> Scheme {
        Scheme(
            name: name,
            shared: shared,
            buildAction: buildAction,
            testAction: testAction,
            runAction: runAction
        )
    }
}

extension BuildAction {
    public static func test(targets: [TargetReference] = []) -> BuildAction {
        BuildAction(
            targets: targets,
            preActions: [ExecutionAction.test()],
            postActions: [ExecutionAction.test()]
        )
    }
}

extension TestAction {
    public static func test(
        targets: [TestableTarget] = [],
        arguments: Arguments? = nil,
        configuration: ConfigurationName = .debug,
        coverage: Bool = true
    ) -> TestAction {
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

extension RunAction {
    public static func test(
        configuration: ConfigurationName = .debug,
        executable: TargetReference? = nil,
        arguments: Arguments? = nil
    ) -> RunAction {
        RunAction(
            configuration: configuration,
            executable: executable,
            arguments: arguments
        )
    }
}

extension ExecutionAction {
    public static func test(
        title: String = "Test Script",
        scriptText: String = "echo Test",
        target: TargetReference? = TargetReference(projectPath: nil, target: "Target")
    ) -> ExecutionAction {
        ExecutionAction(
            title: title,
            scriptText: scriptText,
            target: target
        )
    }
}

extension Arguments {
    public static func test(
        environment: [String: String] = [:],
        launchArguments: [LaunchArgument] = []
    ) -> Arguments {
        Arguments(
            environment: environment,
            launchArguments: launchArguments
        )
    }
}

extension Dependencies {
    public static func test(carthageDependencies: CarthageDependencies? = nil) -> Dependencies {
        Dependencies(carthage: carthageDependencies)
    }
}

extension Plugin {
    public static func test(name: String = "Plugin") -> Plugin {
        Plugin(name: name)
    }
}
