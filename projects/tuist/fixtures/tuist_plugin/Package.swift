// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalPlugin",
    platforms: [.macOS(.v10_15)],
    products: [
        .executable(
            name: "tuist-create-file",
            targets: ["CreateFile"]
        ),
        .executable(
            name: "tuist-inspect-graph",
            targets: ["InspectGraph"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/tuist/tuist", .revision("37d054762")),
    ],
    targets: [
        .target(
            name: "CreateFile",
            dependencies: [
                .product(name: "ProjectAutomation", package: "tuist")
            ]
        ),
        .testTarget(name: "CreateFileTests"),
        .target(
            name: "InspectGraph",
            dependencies: [
                .product(name: "ProjectAutomation", package: "tuist")
            ]
        ),
    ]
)
