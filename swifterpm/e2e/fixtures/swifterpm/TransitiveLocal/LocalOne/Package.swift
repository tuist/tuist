// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LocalOne",
    products: [
        .library(name: "LocalOne", targets: ["LocalOne"]),
    ],
    dependencies: [
        .package(path: "../LocalTwo"),
    ],
    targets: [
        .target(
            name: "LocalOne",
            dependencies: [
                .product(name: "LocalTwo", package: "LocalTwo"),
            ]
        ),
    ]
)
