// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "InspectGraph",
    platforms: [.macOS(.v12)],
    products: [
        .executable(
            name: "inspect-graph",
            targets: ["InspectGraph"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(path: "../../../"),
    ],
    targets: [
        .target(
            name: "InspectGraph",
            dependencies: [
                .product(name: "ProjectAutomation", package: "tuist"),
            ]
        ),
    ]
)
