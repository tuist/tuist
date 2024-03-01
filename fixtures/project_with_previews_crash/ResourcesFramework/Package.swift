// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ResourcesFramework",
    platforms: [.iOS(.v15), .macOS(.v14)],
    products: [
        .library(
            name: "ResourcesFramework",
            type: .static,
            targets: [
                "ResourcesFramework"
            ]
        )
    ],
    targets: [
        .target(
            name: "ResourcesFramework",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
