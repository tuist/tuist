import ProjectDescription
import ProjectDescriptionHelpers

let baseSettings: SettingsDictionary = ["EXCLUDED_ARCHS": "arm64"]

func debugSettings() -> SettingsDictionary {
    var settings = baseSettings
    settings["ENABLE_TESTABILITY"] = "YES"
    return settings
}

func releaseSettings() -> SettingsDictionary {
    baseSettings
}

func modulesTargetsAndSchemes() -> [(targets: [Target], scheme: Scheme)] {
    [
        Target.module(
            name: "TuistSupport",
            hasIntegrationTests: true,
            dependencies: [
                .external(name: "ArgumentParser"),
                .external(name: "Checksum"),
                .external(name: "CombineExt"),
                .external(name: "CryptoSwift"),
                .external(name: "GraphViz"),
                .external(name: "KeychainAccess"),
                .external(name: "Logging"),
                .external(name: "PathKit"),
                .external(name: "Queuer"),
                .external(name: "RxSwift"),
                .external(name: "Signals"),
                .external(name: "Stencil"),
                .external(name: "StencilSwiftKit"),
                .external(name: "Swifter"),
                .external(name: "SwiftToolsSupport-auto"),
                .external(name: "XcodeProj"),
                .external(name: "Zip"),
                .external(name: "SwiftGenKit"),
            ]
        ),
        Target.module(
            name: "TuistKit",
            hasTesting: false,
            hasIntegrationTests: true,
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            integrationTestsDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistEnvKit",
            hasTesting: false,
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistGraph",
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistCore",
            hasIntegrationTests: true,
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ],
            integrationTestsDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistGenerator",
            hasIntegrationTests: true,
            dependencies: [
                .auto,
                .external(name: "SwiftGenKit"),
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ],
            integrationTestsDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistCloud",
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistTasks",
            hasTests: false,
            hasIntegrationTests: true,
            dependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ],
            integrationTestsDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistCache",
            hasIntegrationTests: true,
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ],
            integrationTestsDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistScaffold",
            hasIntegrationTests: true,
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ],
            integrationTestsDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistLoader",
            hasIntegrationTests: true,
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ],
            integrationTestsDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistAsyncQueue",
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistPlugin",
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "ProjectDescription",
            hasTesting: false,
            testDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "ProjectAutomation",
            hasTests: false,
            hasTesting: false
        ),
        Target.module(
            name: "TuistSigning",
            hasIntegrationTests: true,
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ],
            integrationTestsDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistAnalytics",
            hasTesting: false,
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistMigration",
            hasIntegrationTests: true,
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ],
            integrationTestsDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistLinting",
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistDependencies",
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ]
        ),
        Target.module(
            name: "TuistAutomation",
            hasIntegrationTests: true,
            dependencies: [
                .auto,
            ],
            testDependencies: [
                .auto,
            ],
            testingDependencies: [
                .auto,
            ],
            integrationTestsDependencies: [
                .auto,
            ]
        ),
    ]
}

func otherTargets() -> [Target] {
    [
        Target.target(
            name: "tuistenv",
            product: .commandLineTool,
            dependencies: [
                .auto,
            ]
        ),
        Target.target(
            name: "tuist",
            product: .commandLineTool,
            dependencies: [
                .auto,
            ]
        ),
        Target.target(
            name: "TuistIntegrationTests",
            product: .unitTests,
            dependencies: [
                .auto,
            ]
        ),
    ]
}

let modules = modulesTargetsAndSchemes()

let project = Project(
    name: "Tuist",
    options: [
        .textSettings(indentWidth: 4, tabWidth: 4),
    ],
    settings: .settings(
        configurations: [
            .debug(name: "Debug", settings: debugSettings(), xcconfig: nil),
            .release(name: "Release", settings: releaseSettings(), xcconfig: nil),
        ]
    ),
    targets: otherTargets() + modules.map(\.targets).flatMap { $0 },
    schemes: modules.map(\.scheme),
    additionalFiles: ["CHANGELOG.md"]
)
