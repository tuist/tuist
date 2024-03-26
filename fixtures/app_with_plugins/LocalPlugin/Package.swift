// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalPlugin",
    platforms: [.macOS(.v11)],
    products: [
        .executable(
            name: "tuist-local-inspect-graph",
            targets: ["InspectGraph"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/tuist/ProjectAutomation", .exact("4.7.0")),
    ],
    targets: [
        .target(
            name: "InspectGraph",
            dependencies: [
                .product(name: "ProjectAutomation", package: "ProjectAutomation")
            ]
        ),
    ]
)
