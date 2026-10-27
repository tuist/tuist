// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Service",
    products: [
        .library(name: "Service", targets: ["Service"]),
    ],
    dependencies: [
        .package(url: "../Proto.git", from: "1.35.0"),
    ],
    targets: [
        .target(
            name: "Service",
            dependencies: [
                .product(name: "Proto", package: "Proto"),
            ]
        ),
    ]
)
