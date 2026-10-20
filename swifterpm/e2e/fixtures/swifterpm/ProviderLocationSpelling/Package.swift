// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ProviderLocationSpelling",
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", exact: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
            ]
        ),
    ]
)
