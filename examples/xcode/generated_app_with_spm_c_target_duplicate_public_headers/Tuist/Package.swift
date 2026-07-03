// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: ["nanopb": .staticFramework]
)
#endif

let package = Package(
    name: "Deps",
    dependencies: [
        .package(path: "../Nanopb"),
    ]
)
