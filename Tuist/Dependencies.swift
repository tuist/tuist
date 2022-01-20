import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init(
        [
            .package(url: "https://github.com/tuist/XcodeProj", .upToNextMajor(from: "8.5.0")),
            .package(url: "https://github.com/CombineCommunity/CombineExt", .upToNextMajor(from: "1.3.0")),
            .package(url: "https://github.com/apple/swift-tools-support-core", .upToNextMinor(from: "0.2.0")),
            .package(url: "https://github.com/ReactiveX/RxSwift", .upToNextMajor(from: "5.1.1")),
            .package(url: "https://github.com/apple/swift-log", .upToNextMajor(from: "1.4.2")),
            .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", .upToNextMajor(from: "4.2.2")),
            .package(url: "https://github.com/httpswift/swifter", .branch("1e4f51c92d7ca486242d8bf0722b99de2c3531aa")),
            .package(url: "https://github.com/tuist/BlueSignals", .upToNextMajor(from: "1.0.21")),
            .package(url: "https://github.com/marmelroy/Zip", .upToNextMajor(from: "2.1.1")),
            .package(url: "https://github.com/rnine/Checksum", .upToNextMajor(from: "1.0.2")),
            .package(url: "https://github.com/stencilproject/Stencil", .upToNextMajor(from: "0.14.1")),
            .package(url: "https://github.com/SwiftGen/StencilSwiftKit", .upToNextMajor(from: "2.8.0")),
            .package(url: "https://github.com/FabrizioBrancati/Queuer", .upToNextMajor(from: "2.1.1")),
            .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .upToNextMajor(from: "1.4.1")),
            .package(url: "https://github.com/tuist/GraphViz", .branch("tuist")),
            .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.0.0")),
            .package(url: "https://github.com/SwiftGen/SwiftGen", .exact("6.5.0")),
            .package(url: "https://github.com/kylef/PathKit", .upToNextMajor(from: "1.0.0")),
        ],
        productTypes: ["RxSwift": .framework, "Checksum": .framework],
        targetSettings: [
            "TSCTestSupport": ["ENABLE_TESTING_SEARCH_PATHS": "YES"],
            "RxTest": ["ENABLE_TESTING_SEARCH_PATHS": "YES"],
        ]
    ),
    platforms: [.macOS]
)
