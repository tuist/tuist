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

func targets() -> [Target] {
    let executableTargets = [
        Target.target(
            name: "tuistenv",
            product: .commandLineTool,
            dependencies: [
                .target(name: "TuistEnvKit"),
            ]
        ),
        Target.target(
            name: "tuist",
            product: .commandLineTool,
            dependencies: [
                .target(name: "TuistKit"),
                .target(name: "ProjectDescription"),
                .target(name: "ProjectAutomation"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
                .external(name: "GraphViz"),
                .external(name: "ArgumentParser"),
            ],
            settings: .settings(
                base: [
                    "LD_RUNPATH_SEARCH_PATHS": "$(FRAMEWORK_SEARCH_PATHS)",
                ],
                configurations: [
                    .debug(name: "Debug", settings: [:], xcconfig: nil),
                    .release(name: "Release", settings: [:], xcconfig: nil),
                ]
            )
        ),
        Target.target(
            name: "tuistbenchmark",
            product: .commandLineTool,
            dependencies: [
                .external(name: "ArgumentParser"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
            ]
        ),
        Target.target(
            name: "tuistfixturegenerator",
            product: .commandLineTool,
            dependencies: [
                .external(name: "ArgumentParser"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
            ]
        ),
        Target.target(
            name: "TuistIntegrationTests",
            product: .unitTests,
            dependencies: [
                .target(name: "TuistGenerator"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistSupport"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistLoaderTesting"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
                .external(name: "XcodeProj"),
            ]
        ),
    ]
    let moduleTargets = [
        Target.module(
            name: "TuistSupport",
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "ProjectDescription"),
                .external(name: "AnyCodable"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
                .external(name: "XcodeProj"),
                .external(name: "KeychainAccess"),
                .external(name: "CombineExt"),
                .external(name: "Logging"),
                .external(name: "ZIPFoundation"),
                .external(name: "Swifter"),
            ],
            testingDependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
            ]
        ),
        Target.module(
            name: "TuistKit",
            hasTesting: false,
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistSupport"),
                .target(name: "TuistGenerator"),
                .target(name: "TuistAutomation"),
                .target(name: "ProjectDescription"),
                .target(name: "ProjectAutomation"),
                .target(name: "TuistLoader"),
                .target(name: "TuistScaffold"),
                .target(name: "TuistSigning"),
                .target(name: "TuistDependencies"),
                .target(name: "TuistMigration"),
                .target(name: "TuistAsyncQueue"),
                .target(name: "TuistAnalytics"),
                .target(name: "TuistPlugin"),
                .target(name: "TuistGraph"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
                .external(name: "ArgumentParser"),
                .external(name: "GraphViz"),
                .external(name: "AnyCodable"),
            ],
            testDependencies: [
                .target(name: "TuistAutomation"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "ProjectDescription"),
                .target(name: "ProjectAutomation"),
                .target(name: "TuistLoaderTesting"),
                .target(name: "TuistGeneratorTesting"),
                .target(name: "TuistScaffoldTesting"),
                .target(name: "TuistAutomationTesting"),
                .target(name: "TuistSigningTesting"),
                .target(name: "TuistDependenciesTesting"),
                .target(name: "TuistMigrationTesting"),
                .target(name: "TuistAsyncQueueTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistPlugin"),
                .target(name: "TuistPluginTesting"),
                .external(name: "ArgumentParser"),
                .external(name: "GraphViz"),
                .external(name: "AnyCodable"),
            ],
            integrationTestsDependencies: [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "ProjectDescription"),
                .target(name: "ProjectAutomation"),
                .target(name: "TuistLoaderTesting"),
                .target(name: "TuistGraphTesting"),
                .external(name: "XcodeProj"),
            ]
        ),
        Target.module(
            name: "TuistEnvKit",
            hasTesting: false,
            dependencies: [
                .target(name: "TuistSupport"),
                .external(name: "ArgumentParser"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
            ],
            testDependencies: [
                .target(name: "TuistSupportTesting"),
            ]
        ),
        Target.module(
            name: "TuistGraph",
            dependencies: [
                .target(name: "TuistSupport"),
                .external(name: "AnyCodable"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
            ],
            testDependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupport"),
                .target(name: "TuistSupportTesting"),
                .external(name: "XcodeProj"),
            ],
            testingDependencies: [
                .target(name: "TuistSupport"),
                .target(name: "TuistSupportTesting"),
                .external(name: "XcodeProj"),
            ]
        ),
        Target.module(
            name: "TuistCore",
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "ProjectDescription"),
                .target(name: "TuistSupport"),
                .target(name: "TuistGraph"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
                .external(name: "XcodeProj"),
            ],
            testDependencies: [
                .target(name: "TuistSupport"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistSupport"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            integrationTestsDependencies: [
                .target(name: "TuistSupportTesting"),
            ]
        ),
        Target.module(
            name: "TuistGenerator",
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .external(name: "SwiftGenKit"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
                .external(name: "PathKit"),
                .external(name: "StencilSwiftKit"),
                .external(name: "XcodeProj"),
                .external(name: "GraphViz"),
            ],
            testDependencies: [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
                .external(name: "XcodeProj"),
                .external(name: "GraphViz"),
            ],
            testingDependencies: [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
                .external(name: "XcodeProj"),
            ],
            integrationTestsDependencies: [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistSigningTesting"),
                .external(name: "XcodeProj"),
            ]
        ),
        Target.module(
            name: "TuistScaffold",
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
                .external(name: "PathKit"),
                .external(name: "StencilSwiftKit"),
            ],
            testDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistGraphTesting"),
            ],
            integrationTestsDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        ),
        Target.module(
            name: "TuistLoader",
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .target(name: "ProjectDescription"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
                .external(name: "XcodeProj"),
            ],
            testDependencies: [
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistCore"),
                .target(name: "ProjectDescription"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            integrationTestsDependencies: [
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "ProjectDescription"),
            ]
        ),
        Target.module(
            name: "TuistAsyncQueue",
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
                .external(name: "Queuer"),
                .external(name: "XcodeProj"),
            ],
            testDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
                .external(name: "Queuer"),
            ],
            testingDependencies: [
                .target(name: "TuistGraphTesting"),
            ]
        ),
        Target.module(
            name: "TuistPlugin",
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistLoader"),
                .target(name: "TuistSupport"),
                .target(name: "TuistScaffold"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
            ],
            testDependencies: [
                .target(name: "ProjectDescription"),
                .target(name: "TuistLoader"),
                .target(name: "TuistLoaderTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistSupport"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistScaffoldTesting"),
                .target(name: "TuistCoreTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistGraph"),
            ]
        ),
        Target.module(
            name: "ProjectDescription",
            product: .framework,
            hasTesting: false,
            testDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistSupport"),
            ]
        ),
        Target.module(
            name: "ProjectAutomation",
            product: .framework,
            hasTests: false,
            hasTesting: false,
            dependencies: []
        ),
        Target.module(
            name: "TuistSigning",
            hasIntegrationTests: false,
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .external(name: "CryptoSwift"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
            ],
            testDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistGraphTesting"),
            ]
        ),
        Target.module(
            name: "TuistAnalytics",
            hasTests: false,
            hasTesting: false,
            dependencies: [
                .target(name: "TuistAsyncQueue"),
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistLoader"),
                .target(name: "TuistSupport"),
                .external(name: "AnyCodable"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
            ],
            testDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistCoreTesting"),
            ]
        ),
        Target.module(
            name: "TuistMigration",
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
                .external(name: "PathKit"),
                .external(name: "XcodeProj"),
            ],
            testDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistGraphTesting"),
            ],
            integrationTestsDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        ),
        Target.module(
            name: "TuistDependencies",
            dependencies: [
                .target(name: "ProjectDescription"),
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
            ],
            testDependencies: [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistLoaderTesting"),
                .target(name: "TuistSupportTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistGraphTesting"),
                .target(name: "ProjectDescription"),
            ]
        ),
        Target.module(
            name: "TuistAutomation",
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
                .external(name: "XcodeProj"),
                .external(name: "XcbeautifyLib"),
            ],
            testDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistCoreTesting"),
                .target(name: "ProjectDescription"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            integrationTestsDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        ),
    ].flatMap { $0 }

    return executableTargets + moduleTargets + acceptanceTests.map(\.target) + [
        .target(
            name: "TuistAcceptanceTesting",
            product: .staticFramework,
            dependencies: [
                .target(name: "TuistKit"),
                .target(name: "TuistSupportTesting"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
                .sdk(name: "XCTest", type: .framework, status: .optional),
            ]
        ),
    ]
}

let acceptanceTests: [(target: Target, scheme: Scheme)] = ["Build", "GenerateOne", "Test"].map {
    (
        target: .target(
            name: "Tuist\($0)AcceptanceTests",
            product: .unitTests,
            dependencies: [
                .target(name: "TuistAcceptanceTesting"),
                .target(name: "TuistSupportTesting"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "SystemPackage"),
            ]
        ),
        scheme: Scheme(
            name: "Tuist\($0)AcceptanceTests",
            buildAction: BuildAction(targets: ["Tuist\($0)AcceptanceTests"]),
            testAction: .targets(
                [
                    TestableTarget(
                        target: "Tuist\($0)AcceptanceTests",
                        parallelizable: true,
                        randomExecutionOrdering: true
                    ),
                ]
            ),
            runAction: .runAction(
                arguments: Arguments(
                    environmentVariables: [
                        "TUIST_CONFIG_SRCROOT": "$(SRCROOT)",
                        "TUIST_FRAMEWORK_SEARCH_PATHS": "$(FRAMEWORK_SEARCH_PATHS)",
                    ]
                )
            )
        )
    )
}

let project = Project(
    name: "Tuist",
    options: .options(
        textSettings: .textSettings(usesTabs: false, indentWidth: 4, tabWidth: 4)
    ),
    settings: .settings(
        configurations: [
            .debug(name: "Debug", settings: debugSettings(), xcconfig: nil),
            .release(name: "Release", settings: releaseSettings(), xcconfig: nil),
        ]
    ),
    targets: targets(),
    schemes: acceptanceTests.map(\.scheme),
    additionalFiles: [
        "CHANGELOG.md",
        "README.md",
        "Sources/tuist/tuist.docc/**/*.md",
        "Sources/tuist/tuist.docc/**/*.tutorial",
        "Sources/tuist/tuist.docc/**/*.swift",
    ]
)
