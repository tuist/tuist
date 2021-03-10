import ProjectDescription

let deploymentTarget: DeploymentTarget = .macOS(targetVersion: "10.15")
let baseSettings: SettingsDictionary = ["EXCLUDED_ARCHS": "arm64"]

let project = Project(
    name: "Tuist",
    packages: [
        .package(url: "https://github.com/tuist/XcodeProj.git", .upToNextMajor(from: "7.17.0")),
        .package(url: "https://github.com/CombineCommunity/CombineExt.git", .upToNextMajor(from: "1.2.0")),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", .upToNextMinor(from: "0.1.12")),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "5.1.1")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.4.0")),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMajor(from: "4.1.0")),
        .package(url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0")),
        .package(url: "https://github.com/tuist/BlueSignals.git", .upToNextMajor(from: "1.0.21")),
        .package(url: "https://github.com/marmelroy/Zip.git", .upToNextMinor(from: "2.1.1")),
        .package(url: "https://github.com/rnine/Checksum.git", .upToNextMajor(from: "1.0.2")),
    ],
    settings: Settings(configurations: [
        .release(name: "Debug", settings: baseSettings, xcconfig: nil),
        .release(name: "Release", settings: baseSettings, xcconfig: nil),
    ]),
    targets: [
        Target(name: "TuistSupport",
               platform: .macOS,
               product: .staticLibrary,
               bundleId: "io.tuist.TuistSupport",
               deploymentTarget: deploymentTarget,
               infoPlist: .default,
               sources: ["Sources/TuistSupport/**/*.swift"],
               dependencies: [
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
               ],
               settings: Settings(configurations: [
                   .release(name: "Debug", settings: [:], xcconfig: nil),
                   .release(name: "Release", settings: [:], xcconfig: nil),
               ])),
    ]
)
