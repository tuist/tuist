// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalPackage",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "Shared", targets: ["Shared"])],
    targets: [
        .target(name: "Leaf"),
        .target(name: "Shared", dependencies: ["Leaf"]),
    ]
)
