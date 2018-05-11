// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "xcbuddy",
    dependencies: [
        .package(url: "git@github.com:xcbuddy/xcodeproj.git", .revision("b32d1da90732bea8a0be8ffb205a0bcdbb406a68")),
        .package(url: "git@github.com:apple/swift-package-manager.git", .revision("26ab3997142ef464090c63f963d1dafef79a7c06")),
    ],
    targets: [
        .target(
            name: "ProjectDescription",
            dependencies: []),
        .testTarget(
            name: "ProjectDescriptionTests",
            dependencies: ["ProjectDescription"]
        ),
        .target(
            name: "Dependencies",
            dependencies: ["xcodeproj", "Utility"]
        ),
    ]
)
