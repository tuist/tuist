// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LocalPackage",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "LocalLib", targets: ["LocalLib"]),
    ],
    targets: [
        .target(name: "LocalLib"),
    ]
)
