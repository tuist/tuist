// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    platforms: [
        .iOS(.v13),
        .macOS(.v13),
    ],
    products: [
    ],
    dependencies: [
        //      .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.10.0"),
//      .package(url: "https://github.com/fernandolucheti/ProtocolMacro", from: "0.0.1"),
//      .package(url: "https://github.com/alschmut/StructBuilderMacro", from: "0.5.0"),
//      .package(url: "https://github.com/FelixHerrmann/swift-package-list", from: "2.0.0"),
//      .package(url: "https://github.com/lukepistrol/SwiftLintPlugin", from: "0.2.2"),
//      .package(url: "https://github.com/ordo-one/package-benchmark", .upToNextMajor(from: "1.4.0")),
//      .package(url: "https://github.com/Lighter-swift/Lighter", .upToNextMajor(from: "1.0.0")),
//      .package(url: "https://github.com/securevale/swift-confidential-plugin.git", .upToNextMinor(from: "0.4.0")),
//      .package(url: "https://github.com/maiyama18/LicensesPlugin", from: "0.1.0"),
//      .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.0"),
//      .package(url: "https://github.com/p-x9/swift-weak-self-check", from: "0.0.1"),
//      .package(url: "https://github.com/jhonatn/SwiftSafeURL", from: "0.4.2"),

        // experiment packages
//        .package(url: "https://github.com/YIshihara11201/MyMacro", from: "0.1.2"),
        .package(url: "https://github.com/YIshihara11201/MySPMPlugin", from: "1.0.4"),
    ],
    targets: [
    ]
)
