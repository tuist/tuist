// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(path: "../LocalOne"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "LocalOne", package: "LocalOne"),
            ]
        ),
    ]
)
