// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SecondPackage",
    products: [
        .library(name: "SecondPackage", targets: ["SecondPackage"]),
    ],
    targets: [
        .target(name: "SecondPackage"),
    ]
)
