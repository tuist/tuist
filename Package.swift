// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "xpm",
    dependencies: [
        .package(url: "git@github.com:xcode-project-manager/xcodeproj.git", .revision("d003a30d0b0e3b0d422f6c19be5ec7b90e901475")),
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
