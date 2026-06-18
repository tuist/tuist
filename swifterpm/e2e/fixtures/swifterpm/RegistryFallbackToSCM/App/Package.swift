// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "../LocalRegistryFoo", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "RegistryFoo", package: "LocalRegistryFoo"),
            ]
        ),
    ]
)
