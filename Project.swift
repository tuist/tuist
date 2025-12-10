import ProjectDescription
import ProjectDescriptionHelpers

let baseSettings: SettingsDictionary = [:]

func debugSettings() -> SettingsDictionary {
    var settings = baseSettings
    settings["ENABLE_TESTABILITY"] = "YES"
    return settings
}

func inspectBuildPostAction(target: TargetReference) -> ExecutionAction {
    .executionAction(
        title: "Inspect build",
        scriptText: """
        eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"

        tuist inspect build
        """,
        target: target
    )
}

func inspectTestPostAction(target: TargetReference) -> ExecutionAction {
    .executionAction(
        title: "Inspect test",
        scriptText: """
        eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"

        tuist inspect test
        """,
        target: target
    )
}

func releaseSettings() -> SettingsDictionary {
    baseSettings
}

func launchArgumentsFor(_ module: Module) -> [LaunchArgument] {
    switch module {
    case .tuist:
        return [
            .launchArgument(name: "install", isEnabled: false),
            .launchArgument(name: "generate", isEnabled: false),
            .launchArgument(name: "--no-open", isEnabled: false),
        ]
    default:
        return []
    }
}

func acceptanceTestsEnvironmentVariables() -> [String: EnvironmentVariable] {
    [
        "TUIST_CONFIG_SRCROOT": "$(SRCROOT)",
        "TUIST_FRAMEWORK_SEARCH_PATHS": "$(FRAMEWORK_SEARCH_PATHS)",
        "TUIST_AUTH_EMAIL": "tuistrocks@tuist.dev",
        "TUIST_AUTH_PASSWORD": "tuistrocks",
    ]
}

func tuistTestUnitTargets() -> [TestableTarget] {
    var unitTestTargets: [TestableTarget] = Module.allCases.flatMap(\.unitTestTargets).map {
        .testableTarget(target: .target($0.name), parallelization: .enabled)
    }
    if Module.includeEE() {
        unitTestTargets.append(.testableTarget(target: .target("TuistCacheEETests"), parallelization: .enabled))
    }
    return unitTestTargets
}

func schemes() -> [Scheme] {
    var schemes: [Scheme] = [
        .scheme(
            name: "Tuist-Workspace",
            buildAction: .buildAction(
                targets: Module.allCases.flatMap(\.targets).map(\.name).sorted().map {
                    .target($0)
                } + (Module.includeEE() ? [.target("TuistCacheEE"), .target("TuistCacheEETests")] : []),
                postActions: [
                    inspectBuildPostAction(target: "tuist"),
                ],
                runPostActionsOnFailure: true
            ),
            testAction: .targets(
                Module.allCases.flatMap(\.testTargets).map {
                    .testableTarget(target: .target($0.name))
                } + (Module.includeEE() ? [.testableTarget(target: .target("TuistCacheEETests"))] : []),
                postActions: [
                    inspectTestPostAction(target: "tuist"),
                ]
            ),
            runAction: .runAction(
                arguments: .arguments(
                    environmentVariables: acceptanceTestsEnvironmentVariables()
                )
            )
        ),
        .scheme(
            name: "TuistAcceptanceTests",
            buildAction: .buildAction(
                targets: Module.allCases.flatMap(\.acceptanceTestTargets).map(\.name).sorted()
                    .map { .target($0) } + (Module.includeEE() ? [.target("TuistCacheEEAcceptanceTests")] : []),
                postActions: [
                    inspectBuildPostAction(target: "TuistKitAcceptanceTests"),
                ],
                runPostActionsOnFailure: true
            ),
            testAction: .targets(
                Module.allCases.flatMap(\.acceptanceTestTargets).map {
                    .testableTarget(target: .target($0.name))
                } + (Module.includeEE() ? [.testableTarget(target: .target("TuistCacheEEAcceptanceTests"))] : []),
                postActions: [
                    inspectTestPostAction(target: "TuistKitAcceptanceTests"),
                ]
            ),
            runAction: .runAction(
                arguments: .arguments(
                    environmentVariables: acceptanceTestsEnvironmentVariables()
                )
            )
        ),
        .scheme(
            name: "TuistUnitTests",
            buildAction: .buildAction(
                targets: Module.allCases.flatMap(\.unitTestTargets).map(\.name).sorted()
                    .map { .target($0) } + (Module.includeEE() ? [.target("TuistCacheEETests")] : []),
                postActions: [
                    inspectBuildPostAction(target: "TuistKitTests"),
                ],
                runPostActionsOnFailure: true
            ),
            testAction: .targets(
                tuistTestUnitTargets(),
                attachDebugger: false,
                postActions: [
                    inspectTestPostAction(target: "TuistKitTests"),
                ],
                options: .options(
                    language: "en"
                )
            ),
            runAction: .runAction(
                arguments: .arguments(
                    environmentVariables: [
                        "TUIST_CONFIG_SRCROOT": "$(SRCROOT)",
                        "TUIST_FRAMEWORK_SEARCH_PATHS": "$(FRAMEWORK_SEARCH_PATHS)",
                    ]
                )
            )
        ),
        .scheme(
            name: "ProjectDescription",
            buildAction: .buildAction(
                targets: [.target(Module.projectDescription.targetName)],
                postActions: [
                    inspectBuildPostAction(target: "tuist"),
                ],
                runPostActionsOnFailure: true
            ),
            testAction: nil,
            runAction: nil
        )
    ]
    if Module.includeEE() {
        schemes.append(.scheme(
            name: "TuistCacheEEAcceptanceTests",
            buildAction: .buildAction(
                targets: [.target("TuistCacheEEAcceptanceTests")],
                postActions: [
                    inspectBuildPostAction(target: "TuistCacheEEAcceptanceTests"),
                ],
                runPostActionsOnFailure: true
            ),
            testAction: .targets(
                [.testableTarget(target: .target("TuistCacheEEAcceptanceTests"))],
                postActions: [
                    inspectTestPostAction(target: "TuistCacheEEAcceptanceTests"),
                ],
                options: .options(
                    language: "en"
                )
            ),
            runAction: .runAction(
                arguments: .arguments(
                    environmentVariables: acceptanceTestsEnvironmentVariables()
                )
            )
        ))
        schemes.append(.scheme(
            name: "TuistCacheEEUnitTests",
            buildAction: .buildAction(
                targets: [.target("TuistCacheEETests")],
                postActions: [
                    inspectBuildPostAction(target: "TuistCacheEEUnitTests"),
                ],
                runPostActionsOnFailure: true
            ),
            testAction: .targets(
                [.testableTarget(target: .target("TuistCacheEETests"))],
                postActions: [
                    inspectTestPostAction(target: "TuistCacheEETests"),
                ],
                options: .options(
                    language: "en"
                )
            ),
            runAction: .runAction(
                arguments: .arguments(
                    environmentVariables: [
                        "TUIST_CONFIG_SRCROOT": "$(SRCROOT)",
                        "TUIST_FRAMEWORK_SEARCH_PATHS": "$(FRAMEWORK_SEARCH_PATHS)",
                    ]
                )
            )
        ))
    }
    schemes.append(
        contentsOf: Module.allCases.filter(\.isRunnable).map {
            .scheme(
                name: $0.targetName,
                buildAction: .buildAction(
                    targets: [.target($0.targetName)],
                    postActions: [
                        inspectBuildPostAction(target: TargetReference(stringLiteral: $0.targetName)),
                    ],
                    runPostActionsOnFailure: true
                ),
                runAction: .runAction(
                    executable: .target($0.targetName),
                    arguments: .arguments(
                        environmentVariables: [
                            "TUIST_CONFIG_SRCROOT": "$(SRCROOT)",
                            "TUIST_FRAMEWORK_SEARCH_PATHS": "$(FRAMEWORK_SEARCH_PATHS)",
                        ],
                        launchArguments: launchArgumentsFor($0)
                    )
                )
            )
        }
    )

    schemes.append(
        contentsOf: (Module.allCases.compactMap(\.acceptanceTestsTargetName) + (Module.includeEE() ? ["TuistCacheEEAcceptanceTests"]: [])).map {
            .scheme(
                name: $0,
                hidden: true,
                buildAction: .buildAction(
                    targets: [.target($0)],
                    postActions: [
                        inspectBuildPostAction(target: TargetReference(stringLiteral: $0)),
                    ],
                    runPostActionsOnFailure: true
                ),
                testAction: .targets(
                    [.testableTarget(target: .target($0))],
                    postActions: [
                        inspectTestPostAction(target: TargetReference(stringLiteral: $0)),
                    ]
                ),
                runAction: .runAction(
                    arguments: .arguments(
                        environmentVariables: acceptanceTestsEnvironmentVariables()
                    )
                )
            )
        }
    )

    return schemes
}

let project = Project(
    name: "Tuist",
    options: .options(
        automaticSchemesOptions: .disabled,
        textSettings: .textSettings(usesTabs: false, indentWidth: 4, tabWidth: 4)
    ),
    settings: .settings(
        configurations: [
            .debug(name: "Debug", settings: debugSettings(), xcconfig: nil),
            .release(name: "Release", settings: releaseSettings(), xcconfig: nil),
        ]
    ),
    targets: Module.allTargets(),
    schemes: schemes(),
    additionalFiles: []
)
