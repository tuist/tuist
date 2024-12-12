// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FirstPackage",
    products: [
        .library(name: "FirstPackage", targets: ["FirstPackage"]),
    ],
    dependencies: [
        .package(path: "../SecondPackage"),
    ],
    targets: [
        .target(name: "FirstPackage", dependencies: [.product(name: "SecondPackage", package: "SecondPackage")]),
    ]
)
