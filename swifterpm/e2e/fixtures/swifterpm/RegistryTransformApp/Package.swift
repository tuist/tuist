// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RegistryTransformApp",
    dependencies: [
        .package(url: "https://github.com/example/RegistryFoo.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "RegistryFoo", package: "RegistryFoo"),
            ]
        ),
    ]
)
