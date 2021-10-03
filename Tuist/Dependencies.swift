import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init(
        [
            .package(url: "https://github.com/tuist/XcodeProj.git", .upToNextMajor(from: "8.3.1")),
            .package(url: "https://github.com/CombineCommunity/CombineExt.git", .upToNextMajor(from: "1.3.0")),
            .package(url: "https://github.com/apple/swift-tools-support-core.git", .upToNextMinor(from: "0.2.0")),
            .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "5.1.1")),
            .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.4.2")),
            .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMajor(from: "4.2.2")),
            .package(url: "https://github.com/fortmarek/swifter.git", .branch("stable")),
            .package(url: "https://github.com/tuist/BlueSignals.git", .upToNextMajor(from: "1.0.21")),
            .package(url: "https://github.com/maparoni/Zip.git", .revision("059e7346082d02de16220cd79df7db18ddeba8c3")),
            .package(url: "https://github.com/rnine/Checksum.git", .upToNextMajor(from: "1.0.2")),
            .package(url: "https://github.com/stencilproject/Stencil.git", .upToNextMajor(from: "0.14.1")),
            .package(url: "https://github.com/SwiftGen/StencilSwiftKit.git", .upToNextMajor(from: "2.8.0")),
            .package(url: "https://github.com/FabrizioBrancati/Queuer.git", .upToNextMajor(from: "2.1.1")),
            .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMajor(from: "1.4.1")),
            .package(url: "https://github.com/tuist/GraphViz.git", .branch("tuist")),
            .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "0.4.3")),
            .package(url: "https://github.com/fortmarek/SwiftGen", .branch("stable")),
            .package(url: "https://github.com/kylef/PathKit.git", .upToNextMajor(from: "1.0.0")),
        ],
        deploymentTargets: [.macOS(targetVersion: "10.15")]
    ),
    platforms: [.macOS]
)
