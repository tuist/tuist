import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init(
        [
            .package(url: "https://github.com/tuist/XcodeProj.git", .upToNextMajor(from: "8.8.0")),
            .package(url: "https://github.com/CombineCommunity/CombineExt.git", .upToNextMajor(from: "1.8.0")),
            .package(url: "https://github.com/apple/swift-tools-support-core.git", .upToNextMinor(from: "0.3.0")),
            .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.4.4")),
            .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMajor(from: "4.2.2")),
            .package(url: "https://github.com/httpswift/swifter.git", .revision("1e4f51c92d7ca486242d8bf0722b99de2c3531aa")),
            .package(
                url: "https://github.com/fortmarek/ZIPFoundation.git",
                .revision("9dbe729b90202c19d0fe1010f1430fa75a576cd3")
            ),
            .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.6"),
            .package(url: "https://github.com/rnine/Checksum.git", .upToNextMajor(from: "1.0.2")),
            .package(url: "https://github.com/stencilproject/Stencil.git", .upToNextMajor(from: "0.15.1")),
            .package(url: "https://github.com/SwiftGen/StencilSwiftKit.git", .exact("2.9.0")),
            .package(url: "https://github.com/FabrizioBrancati/Queuer.git", .upToNextMajor(from: "2.1.1")),
            .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMajor(from: "1.6.0")),
            .package(url: "https://github.com/SwiftDocOrg/GraphViz.git", .exact("0.2.0")),
            .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.1.4")),
            .package(url: "https://github.com/SwiftGen/SwiftGen", .exact("6.5.0")),
            .package(url: "https://github.com/apollographql/apollo-ios.git", .upToNextMajor(from: "1.0.0")),
        ]
    ),
    platforms: [.macOS]
)
