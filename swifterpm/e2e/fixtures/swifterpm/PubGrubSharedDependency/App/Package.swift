// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "../A", exact: "1.0.0"),
        .package(url: "../B", exact: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: ["A", "B"]
        ),
    ]
)
