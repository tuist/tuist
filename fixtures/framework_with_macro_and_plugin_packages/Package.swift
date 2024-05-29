// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    platforms: [
        .iOS(.v13),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "Framework",
            targets: ["Framework"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/alschmut/StructBuilderMacro", from: "0.5.0"),
        .package(url: "https://github.com/lukepistrol/SwiftLintPlugin", from: "0.2.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.10.0"),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .product(name: "Buildable", package: "StructBuilderMacro"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            plugins: [
                .plugin(name: "SwiftLint", package: "SwiftLintPlugin"),
            ]
        ),
    ]
)
