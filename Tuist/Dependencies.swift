import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: [
        .package(url: "https://github.com/apollographql/apollo-ios.git", .exact("1.0.5")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.2"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.2"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", from: "0.5.1"),
        .package(url: "https://github.com/CombineCommunity/CombineExt.git", from: "1.8.0"),
        .package(url: "https://github.com/FabrizioBrancati/Queuer.git", from: "2.1.1"),
        .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.7"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .revision("22bfd0ad22e1b2057088180e8e9c66e204755098")),
        .package(url: "https://github.com/httpswift/swifter.git", .revision("1e4f51c92d7ca486242d8bf0722b99de2c3531aa")),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.6.0"),
        .package(url: "https://github.com/rnine/Checksum.git", from: "1.0.2"),
        .package(url: "https://github.com/stencilproject/Stencil.git", .exact("0.14.2")),
        .package(url: "https://github.com/SwiftDocOrg/GraphViz.git", .exact("0.2.0")),
        .package(url: "https://github.com/SwiftGen/StencilSwiftKit.git", .exact("2.9.0")),
        .package(url: "https://github.com/SwiftGen/SwiftGen", .exact("6.5.1")),
        .package(url: "https://github.com/tuist/XcodeProj.git", .exact("8.9.0")),
    ],
    platforms: [.macOS]
)
