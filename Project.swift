import ProjectDescription

let deploymentTarget: DeploymentTarget = .macOS(targetVersion: "10.15")
let baseSettings: SettingsDictionary = ["EXCLUDED_ARCHS": "arm64"]

func debugSettings() -> SettingsDictionary {
    var settings = baseSettings
    settings["ENABLE_TESTABILITY"] = "YES"
    return settings
}

func releaseSettings() -> SettingsDictionary {
    var settings = baseSettings
    return settings
}

let packages: [Package] = [
    .package(url: "https://github.com/tuist/XcodeProj.git", .upToNextMajor(from: "7.17.0")),
    .package(url: "https://github.com/CombineCommunity/CombineExt.git", .upToNextMajor(from: "1.3.0")),
    .package(url: "https://github.com/apple/swift-tools-support-core.git", .upToNextMinor(from: "0.2.12")),
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
               deploymentTarget: deploymentTarget,
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
               deploymentTarget: deploymentTarget,
               infoPlist: .default,
               sources: ["Tests/ProjectDescriptionTests/**/*.swift"],
               dependencies: [
                .target(name: "ProjectDescription"),
                .target(name: "TuistSupportTesting")
               ],
               settings: Settings(configurations: [
                   .debug(name: "Debug", settings: [:], xcconfig: nil),
                   .release(name: "Release", settings: [:], xcconfig: nil),
               ]))
    ]
}

func module(name: String, product: Product = .staticLibrary, dependencies: [TargetDependency]) -> [Target] {
    var testDependencies = dependencies + [.target(name: "Tuist\(name)"), .target(name: "Tuist\(name)Testing"), .package(product: "RxBlocking")]
    var testingDependencies = dependencies + [.target(name: "Tuist\(name)")]
    return [
        Target(name: "Tuist\(name)",
               platform: .macOS,
               product: product,
               bundleId: "io.tuist.Tuist\(name)",
               deploymentTarget: deploymentTarget,
               infoPlist: .default,
               sources: ["Sources/Tuist\(name)/**/*.swift"],
               dependencies: dependencies,
               settings: Settings(configurations: [
                   .debug(name: "Debug", settings: [:], xcconfig: nil),
                   .release(name: "Release", settings: [:], xcconfig: nil),
               ])),
        Target(name: "Tuist\(name)Tests",
               platform: .macOS,
               product: .unitTests,
               bundleId: "io.tuist.Tuist\(name)Tests",
               deploymentTarget: deploymentTarget,
               infoPlist: .default,
               sources: ["Tests/Tuist\(name)Tests/**/*.swift"],
               dependencies: testDependencies,
               settings: Settings(configurations: [
                   .debug(name: "Debug", settings: [:], xcconfig: nil),
                   .release(name: "Release", settings: [:], xcconfig: nil),
               ])),
        Target(name: "Tuist\(name)Testing",
               platform: .macOS,
               product: .staticLibrary,
               bundleId: "io.tuist.Tuist\(name)Testing",
               deploymentTarget: deploymentTarget,
               infoPlist: .default,
               sources: ["Sources/Tuist\(name)Testing/**/*.swift"],
               dependencies: testingDependencies,
               settings: Settings(configurations: [
                   .debug(name: "Debug", settings: [:], xcconfig: nil),
                   .release(name: "Release", settings: [:], xcconfig: nil),
               ]))
    ]
}

func targets() -> [Target] {
    var targets: [Target] = []
    targets.append(contentsOf: module(name: "Support", dependencies: [
        .package(product: "CombineExt"),
        .package(product: "SwiftToolsSupport-auto"),
        .package(product: "RxSwift"),
        .package(product: "RxRelay"),
        .package(product: "Logging"),
        .package(product: "KeychainAccess"),
        .package(product: "Swifter"),
        .package(product: "Signals"),
        .package(product: "Zip"),
        .package(product: "Checksum"),
    ]))
    targets.append(contentsOf: projectDescription())
    return targets
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
