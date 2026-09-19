// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [
        "ReproCore": .framework,
    ]
)
#endif

let package = Package(
    name: "Dependencies",
    dependencies: [
        .package(path: "../Package"),
    ]
)
