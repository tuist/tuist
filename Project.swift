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
    .package(url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0")),
    .package(url: "https://github.com/tuist/BlueSignals.git", .upToNextMajor(from: "1.0.21")),
    .package(url: "https://github.com/marmelroy/Zip.git", .upToNextMinor(from: "2.1.1")),
    .package(url: "https://github.com/rnine/Checksum.git", .upToNextMajor(from: "1.0.2")),
]

func projectDescription() -> [Target] {
    [
        Target(name: "ProjectDescription",
               platform: .macOS,
               product: .framework,
               bundleId: "io.tuist.ProjectDescription",
               deploymentTarget: Constants.deploymentTarget,
               infoPlist: .default,
               sources: ["Sources/ProjectDescription/**/*.swift"],
               dependencies: [],
               settings: Settings(configurations: [
                   .debug(name: "Debug", settings: [:], xcconfig: nil),
                   .release(name: "Release", settings: [:], xcconfig: nil),
               ])),
        Target(name: "ProjectDescriptionTests",
               platform: .macOS,
               product: .unitTests,
               bundleId: "io.tuist.ProjectDescriptionTests",
               deploymentTarget: Constants.deploymentTarget,
               infoPlist: .default,
               sources: ["Tests/ProjectDescriptionTests/**/*.swift"],
               dependencies: [
                .target(name: "ProjectDescription"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistSupport"),
               ],
               settings: Settings(configurations: [
                   .debug(name: "Debug", settings: [:], xcconfig: nil),
                   .release(name: "Release", settings: [:], xcconfig: nil),
               ]))
    ]
}

func targets() -> [Target] {
    return [
        Target.module(
            name: "Support",
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
            ]
        ),
        Target.module(
            name: "Graph",
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
            name: "Core",
            dependencies: [
                .target(name: "TuistSupport"),
                .target(name: "TuistGraph"),
                .package(product: "XcodeProj"),
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
                .target(name: "TuistCore"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        ),
        projectDescription()
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
