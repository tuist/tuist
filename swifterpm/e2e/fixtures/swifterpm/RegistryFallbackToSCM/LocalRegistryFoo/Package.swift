// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RegistryFoo",
    products: [
        .library(name: "RegistryFoo", targets: ["RegistryFoo"]),
    ],
    targets: [
        .target(name: "RegistryFoo"),
    ]
)
