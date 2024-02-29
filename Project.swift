import ProjectDescription
import ProjectDescriptionHelpers

let baseSettings: SettingsDictionary = [:]

func debugSettings() -> SettingsDictionary {
    var settings = baseSettings
    settings["ENABLE_TESTABILITY"] = "YES"
    return settings
}

func releaseSettings() -> SettingsDictionary {
    baseSettings
}

func schemes() -> [Scheme] {
    var schemes: [Scheme] = [
        .scheme(
            name: "Tuist-Workspace",
            buildAction: .buildAction(targets: Module.allCases.flatMap(\.targets).map(\.name).sorted().map { .target($0) }),
            testAction: .targets(
                Module.allCases.flatMap(\.testTargets).map { .testableTarget(target: .target($0.name)) }
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
            name: "TuistAcceptanceTests",
            buildAction: .buildAction(
                targets: Module.allCases.flatMap(\.acceptanceTestTargets).map(\.name).sorted()
                    .map { .target($0) }
            ),
            testAction: .targets(
                Module.allCases.flatMap(\.acceptanceTestTargets).map { .testableTarget(target: .target($0.name)) }
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
            name: "TuistUnitTests",
            buildAction: .buildAction(
                targets: Module.allCases.flatMap(\.unitTestTargets).map(\.name).sorted()
                    .map { .target($0) }
            ),
            testAction: .targets(
                Module.allCases.flatMap(\.unitTestTargets).map { .testableTarget(target: .target($0.name)) }
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
    ]
    schemes.append(contentsOf: Module.allCases.filter(\.isRunnable).map {
        .scheme(
            name: $0.targetName,
            buildAction: .buildAction(targets: [.target($0.targetName)]),
            runAction: .runAction(
                executable: .target($0.targetName),
                arguments: .arguments(
                    environmentVariables: [
                        "TUIST_CONFIG_SRCROOT": "$(SRCROOT)",
                        "TUIST_FRAMEWORK_SEARCH_PATHS": "$(FRAMEWORK_SEARCH_PATHS)",
                    ]
                )
            )
        )
    })

    schemes.append(contentsOf: Module.allCases.compactMap(\.acceptanceTestsTargetName).map {
        .scheme(
            name: $0,
            hidden: true,
            buildAction: .buildAction(targets: [.target($0)]),
            testAction: .targets([.testableTarget(target: .target($0))]),
            runAction: .runAction(
                arguments: .arguments(
                    environmentVariables: [
                        "TUIST_CONFIG_SRCROOT": "$(SRCROOT)",
                        "TUIST_FRAMEWORK_SEARCH_PATHS": "$(FRAMEWORK_SEARCH_PATHS)",
                    ]
                )
            )
        )
    })

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
    targets: Module.allCases.flatMap(\.targets),
    schemes: schemes(),
    additionalFiles: [
        "CHANGELOG.md",
        "README.md",
        "docs/Sources/tuist/tuist.docc/**/*.md",
        "docs/Sources/tuist/tuist.docc/**/*.tutorial",
        "docs/Sources/tuist/tuist.docc/**/*.swift",
    ]
)
