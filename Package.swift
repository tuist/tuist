// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "xpm",
    dependencies: [
        .package(url: "git@github.com:xcode-project-manager/xcodeproj.git", .revision("1ad8b0739963d9cc9592b9616a2f027ade7c93ab")),
        .package(url: "https://github.com/apple/swift-package-manager", from: "0.2.0"),
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
