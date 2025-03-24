// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ResourcesFramework",
    platforms: [.iOS(.v13), .macOS(.v11)],
    products: [
        .library(name: "ResourcesFramework", targets: ["ResourcesFramework"]),
    ],
    targets: [
        .target(
            name: "ResourcesFramework",
            path: "Sources",
            resources: [.process("greeting.txt")]
        ),
    ]
)
