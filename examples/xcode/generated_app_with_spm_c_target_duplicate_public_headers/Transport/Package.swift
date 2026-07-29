// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Transport",
    products: [
        .library(name: "Transport", targets: ["Transport"]),
    ],
    dependencies: [
        .package(path: "../Nanopb"),
    ],
    targets: [
        .target(
            name: "Transport",
            dependencies: [
                .product(name: "nanopb", package: "Nanopb"),
            ],
            path: ".",
            sources: [
                "transport.c",
                "generated.nanopb.h",
            ],
            publicHeadersPath: "include"
        ),
    ]
)
