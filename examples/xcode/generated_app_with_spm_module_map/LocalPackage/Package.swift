// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LocalPackage",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LocalLib", targets: ["LocalLib"]),
    ],
    targets: [
        .target(name: "LocalLib", dependencies: ["LocalObjcLib"]),
        .target(name: "LocalObjcLib"),
    ]
)
