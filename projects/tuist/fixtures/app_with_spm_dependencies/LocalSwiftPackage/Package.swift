// swift-tools-version:5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalSwiftPackage",
    defaultLocalization: "en",
    platforms: [.iOS(.v13)],
    products: [.library(name: "Styles", targets: ["Styles"]), .library(name: "TestsSupport", targets: ["TestsSupport"])],
    dependencies: [.snapshotTesting],
    targets: [
        .target(
            name: "Styles",
            resources: [
                .process("Resources/Fonts"),
                .copy("Resources/jsonFile.json"), // copy rule, single file
                .copy("Resources/Playground.playground"), // copy rule, opaque file
                .copy("Resources/www"), // copy rule, directory
            ]
        ),
        .target(
            name: "TestsSupport",
            dependencies: [.product(name: "SnapshotTesting", package: "swift-snapshot-testing")]
        ),
        .testTarget(
            name: "StylesTests",
            dependencies: ["TestsSupport", "Styles"].map {
                Target.Dependency(stringLiteral: $0)
            }
        ),
    ]
)

extension Package.Dependency {
    static let snapshotTesting: Package.Dependency = .package(
        url: "https://github.com/pointfreeco/swift-snapshot-testing",
        .upToNextMajor(from: "1.10.0")
    )
}
