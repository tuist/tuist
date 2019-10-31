import Foundation
@testable import ProjectDescription

extension TuistConfig {
    static func test(generationOptions: [TuistConfig.GenerationOptions] = []) -> TuistConfig {
        return TuistConfig(generationOptions: generationOptions)
    }
}

extension Workspace {
    static func test(name: String = "Workspace",
                     projects: [Path] = [],
                     additionalFiles: [FileElement] = []) -> Workspace {
        return Workspace(name: name,
                         projects: projects,
                         additionalFiles: additionalFiles)
    }
}

extension Project {
    static func test(name: String = "Project",
                     settings: Settings? = nil,
                     targets: [Target] = [],
                     additionalFiles: [FileElement] = []) -> Project {
        return Project(name: name,
                       settings: settings,
                       targets: targets,
                       additionalFiles: additionalFiles)
    }
}

extension Target {
    static func test(name: String = "Target",
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
                     environment: [String: String] = [:]) -> Target {
        return Target(name: name,
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
    static func test(name: String = "Action",
                     tool: String? = nil,
                     path: Path? = nil,
                     order: Order = .pre,
                     arguments: [String] = []) -> TargetAction {
        return TargetAction(name: name,
                            tool: tool,
                            path: path,
                            order: order,
                            arguments: arguments)
    }
}

extension Scheme {
    static func test(name: String = "Scheme",
                     shared: Bool = false,
                     buildAction: BuildAction? = nil,
                     testAction: TestAction? = nil,
                     runAction: RunAction? = nil) -> Scheme {
        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction)
    }
}

extension BuildAction {
    static func test(targets: [String] = []) -> BuildAction {
        return BuildAction(targets: targets,
                           preActions: [ExecutionAction.test()],
                           postActions: [ExecutionAction.test()])
    }
}

extension TestAction {
    static func test(targets: [String] = [],
                     arguments: Arguments? = nil,
                     config: PresetBuildConfiguration = .debug,
                     coverage: Bool = true) -> TestAction {
        return TestAction(targets: targets,
                          arguments: arguments,
                          config: config,
                          coverage: coverage,
                          preActions: [ExecutionAction.test()],
                          postActions: [ExecutionAction.test()])
    }
}

extension RunAction {
    static func test(config: PresetBuildConfiguration = .debug,
                     executable: String? = nil,
                     arguments: Arguments? = nil) -> RunAction {
        return RunAction(config: config,
                         executable: executable,
                         arguments: arguments)
    }
}

extension ExecutionAction {
    static func test(title: String = "Test Script",
                     scriptText: String = "echo Test",
                     target: String? = "Target") -> ExecutionAction {
        return ExecutionAction(title: title,
                               scriptText: scriptText,
                               target: target)
    }
}

extension Arguments {
    static func test(environment: [String: String] = [:],
                     launch: [String: Bool] = [:]) -> Arguments {
        return Arguments(environment: environment,
                         launch: launch)
    }
}
