// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalPackage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DynamicProduct", type: .dynamic, targets: ["DynamicModule"]),
        .library(name: "StaticProduct", type: .static, targets: ["StaticModule"]),
        .library(name: "AutomaticProduct", targets: ["AutomaticModule"]),
        .library(name: "AutomaticDynamicProduct", targets: ["PromotedModule"]),
        .library(name: "TestOnlyProduct", targets: ["TestOnlyModule"]),
    ],
    targets: [
        .target(name: "DynamicModule"),
        .target(name: "StaticModule"),
        .target(name: "AutomaticModule"),
        .target(name: "PromotedModule"),
        .target(name: "TestOnlyModule"),
    ]
)
