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

extension TargetScript {
    public static func test(
        name: String = "Action",
        tool: String = "",
        order: Order = .pre,
        arguments: [String] = [],
        inputPaths: [FileListGlob] = [],
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
        .scheme(
            name: name,
            shared: shared,
            buildAction: buildAction,
            testAction: testAction,
            runAction: runAction
        )
    }
}

extension BuildAction {
    public static func test(targets: [Target] = []) -> BuildAction {
        .buildAction(
            targets,
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
        arguments: Arguments? = nil,
        options: RunActionOptions = .options()
    ) -> RunAction {
        RunAction(
            configuration: configuration,
            executable: executable,
            arguments: arguments,
            options: options
        )
    }
}

extension ExecutionAction {
    public static func test(
        title: String = "Test Script",
        scriptText: String = "echo Test",
        target: TargetReference? = .target("Target")
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
            environmentVariables: environment.mapValues { .init(stringLiteral: $0) },
            launchArguments: launchArguments
        )
    }
}

extension Plugin {
    public static func test(name: String = "Plugin") -> Plugin {
        Plugin(name: name)
    }
}
