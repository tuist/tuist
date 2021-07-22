import ProjectDescription
import ProjectDescriptionHelpers

let baseSettings: SettingsDictionary = ["EXCLUDED_ARCHS": "arm64"]

func debugSettings() -> SettingsDictionary {
    var settings = baseSettings
    settings["ENABLE_TESTABILITY"] = "YES"
    return settings
}

func releaseSettings() -> SettingsDictionary {
    return baseSettings
}

let packages: [Package] = [
    .package(url: "https://github.com/tuist/XcodeProj.git", .upToNextMajor(from: "8.0.0")),
    .package(url: "https://github.com/CombineCommunity/CombineExt.git", .upToNextMajor(from: "1.3.0")),
    .package(url: "https://github.com/apple/swift-tools-support-core.git", .upToNextMinor(from: "0.2.0")),
    .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "5.1.1")),
    .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.4.0")),
    .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMajor(from: "4.2.2")),
    .package(url: "https://github.com/fortmarek/swifter.git", .branch("stable")),
    .package(url: "https://github.com/tuist/BlueSignals.git", .upToNextMajor(from: "1.0.21")),
    .package(url: "https://github.com/marmelroy/Zip.git", .upToNextMinor(from: "2.1.1")),
    .package(url: "https://github.com/rnine/Checksum.git", .upToNextMajor(from: "1.0.2")),
    .package(url: "https://github.com/stencilproject/Stencil.git", .upToNextMajor(from: "0.14.1")),
    .package(url: "https://github.com/SwiftGen/StencilSwiftKit.git", .upToNextMajor(from: "2.8.0")),
    .package(url: "https://github.com/FabrizioBrancati/Queuer.git", .upToNextMajor(from: "2.1.1")),
    .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMajor(from: "1.4.1")),
    .package(url: "https://github.com/tuist/GraphViz.git", .branch("tuist")),
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "0.4.3")),
    .package(url: "https://github.com/fortmarek/SwiftGen", .branch("stable")),
    .package(url: "https://github.com/kylef/PathKit.git", .upToNextMajor(from: "1.0.0")),
]

func targets() -> [Target] {
    return [
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
            ]
        ),
    ]
    + [
        Target.module(
            name: "TuistSupport",
            product: .framework,
            hasIntegrationTests: true,
            dependencies: [
                .package(product: "CombineExt"),
                .package(product: "SwiftToolsSupport-auto"),
                .package(product: "RxSwift"),
                .package(product: "RxRelay"),
                .package(product: "RxBlocking"),
                .package(product: "Logging"),
                .package(product: "KeychainAccess"),
                .package(product: "Swifter"),
                .package(product: "Signals"),
                .package(product: "Zip"),
                .package(product: "Checksum"),
                .package(product: "StencilSwiftKit"),
                .package(product: "SwiftGenKit"),
                .package(product: "Stencil"),
                .package(product: "XcodeProj"),
                .package(product: "Queuer"),
                .package(product: "CryptoSwift"),
                .package(product: "GraphViz"),
                .package(product: "ArgumentParser"),
                .package(product: "PathKit"),
            ]
        ),
        Target.module(
            name: "TuistKit",
            hasTesting: false,
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistSupport"),
                .target(name: "TuistGenerator"),
                .target(name: "TuistCache"),
                .target(name: "TuistAutomation"),
                .target(name: "ProjectDescription"),
                .target(name: "ProjectAutomation"),
                .target(name: "TuistLoader"),
                .target(name: "TuistInsights"),
                .target(name: "TuistScaffold"),
                .target(name: "TuistSigning"),
                .target(name: "TuistDependencies"),
                .target(name: "TuistLinting"),
                .target(name: "TuistLab"),
                .target(name: "TuistDoc"),
                .target(name: "TuistMigration"),
                .target(name: "TuistAsyncQueue"),
                .target(name: "TuistAnalytics"),
                .target(name: "TuistPlugin"),
                .target(name: "TuistGraph"),
                .target(name: "TuistTasks"),
            ],
            testDependencies: [
                .target(name: "TuistAutomation"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "ProjectDescription"),
                .target(name: "ProjectAutomation"),
                .target(name: "TuistLoaderTesting"),
                .target(name: "TuistCacheTesting"),
                .target(name: "TuistGeneratorTesting"),
                .target(name: "TuistScaffoldTesting"),
                .target(name: "TuistLabTesting"),
                .target(name: "TuistAutomationTesting"),
                .target(name: "TuistSigningTesting"),
                .target(name: "TuistDependenciesTesting"),
                .target(name: "TuistLintingTesting"),
                .target(name: "TuistMigrationTesting"),
                .target(name: "TuistDocTesting"),
                .target(name: "TuistAsyncQueueTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistPlugin"),
                .target(name: "TuistPluginTesting"),
                .target(name: "TuistTasksTesting"),
            ],
            integrationTestsDependencies: [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "ProjectDescription"),
                .target(name: "ProjectAutomation"),
                .target(name: "TuistLoaderTesting"),
                .target(name: "TuistLabTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        ),
        Target.module(
            name: "TuistDoc",
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
            ],
            testDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCore"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistSupport"),
            ],
            testingDependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
            ]
        ),
        Target.module(
            name: "TuistEnvKit",
            hasTesting: false,
            dependencies: [
                .target(name: "TuistSupport"),
            ],
            testDependencies: [
                .target(name: "TuistSupportTesting"),
            ]
        ),
        Target.module(
            name: "TuistGraph",
            dependencies: [
                .target(name: "TuistSupport"),
            ],
            testDependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupport"),
                .target(name: "TuistSupportTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistSupport"),
                .target(name: "TuistSupportTesting"),
            ]
        ),
        Target.module(
            name: "TuistCore",
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "ProjectDescription"),
                .target(name: "TuistSupport"),
                .target(name: "TuistGraph"),
            ],
            testDependencies: [
                .target(name: "TuistSupport"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting")
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
            ],
            testDependencies: [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            integrationTestsDependencies: [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistSigningTesting"),
            ]
        ),
        Target.module(
            name: "TuistLab",
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
            ],
            testDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraphTesting"),
            ]
        ),
        Target.module(
            name: "TuistTasks",
            hasTests: false,
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistSupport"),
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
            name: "TuistCache",
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .target(name: "TuistLab"),
            ],
            testDependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .target(name: "TuistLab"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .target(name: "TuistLab"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistSupportTesting"),
            ],
            integrationTestsDependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .target(name: "TuistLab"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        ),
        Target.module(
            name: "TuistScaffold",
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
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
            name: "TuistPlugin",
            dependencies: [
                .target(name: "TuistGraph"),
                .target(name: "TuistLoader"),
                .target(name: "TuistSupport"),
                .target(name: "TuistScaffold"),
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
            hasTesting: false,
            testDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistSupport"),
            ]
        ),
        Target.module(
            name: "ProjectAutomation",
            hasTests: false,
            hasTesting: false
        ),
        Target.module(
            name: "TuistInsights",
            hasTesting: false,
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
            ],
            testDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            integrationTestsDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        ),
        Target.module(
            name: "TuistSigning",
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
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
            name: "TuistAnalytics",
            hasTesting: false,
            dependencies: [
                .target(name: "TuistAsyncQueue"),
                .target(name: "TuistCore"),
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
            name: "TuistLinting",
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
            ],
            testDependencies: [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ],
            testingDependencies: [
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
            ],
            testDependencies: [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistLoaderTesting"),
                .target(name: "TuistSupportTesting"),
            ],
            testingDependencies: [
                .target(name: "TuistGraphTesting"),
            ]
        ),
        Target.module(
            name: "TuistAutomation",
            hasIntegrationTests: true,
            dependencies: [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
            ],
            testDependencies: [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting")
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
        )
    ]
    .flatMap { $0 }
}

let project = Project(
    name: "Tuist",
    packages: packages,
    settings: Settings(configurations: [
        .debug(name: "Debug", settings: debugSettings(), xcconfig: nil),
        .release(name: "Release", settings: releaseSettings(), xcconfig: nil),
    ]),
    targets: targets()
)
