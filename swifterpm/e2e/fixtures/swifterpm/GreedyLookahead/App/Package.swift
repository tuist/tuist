// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "../Proto.git", exact: "1.35.1"),
        .package(url: "../Service.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Proto", package: "Proto"),
                .product(name: "Service", package: "Service"),
            ]
        ),
    ]
)
