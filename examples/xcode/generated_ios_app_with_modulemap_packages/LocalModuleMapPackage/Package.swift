// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LocalModuleMapPackage",
    products: [
        .library(name: "LocalModuleMap", targets: ["LocalModuleMap"]),
    ],
    targets: [
        .target(
            name: "LocalModuleMap",
            publicHeadersPath: "include"
        ),
    ]
)
