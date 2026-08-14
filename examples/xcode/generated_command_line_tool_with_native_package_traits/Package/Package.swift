// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FeaturePackage",
    products: [
        .library(name: "FeaturePackage", targets: ["FeaturePackage"]),
    ],
    traits: [
        .trait(name: "NativeIntegration"),
    ],
    targets: [
        .target(name: "FeaturePackage"),
    ]
)
