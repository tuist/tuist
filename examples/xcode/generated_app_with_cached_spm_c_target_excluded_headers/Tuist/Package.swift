// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Deps",
    dependencies: [
        .package(path: "../VendoredPkg"),
    ]
)
