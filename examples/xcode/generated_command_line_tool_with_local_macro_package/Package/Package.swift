// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "MacroPackage",
    products: [
        .library(name: "ReproCore", targets: ["ReproCore"]),
    ],
    targets: [
        .macro(name: "ReproMacro"),
        .target(
            name: "ReproCore",
            dependencies: ["ReproMacro"]
        ),
    ]
)
