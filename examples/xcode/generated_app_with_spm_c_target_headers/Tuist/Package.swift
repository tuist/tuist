// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription
let packageSettings = PackageSettings(
    productTypes: ["CLib": .staticFramework]
)
#endif

let package = Package(
    name: "Deps",
    dependencies: [
        .package(path: "../CLibPkg"),
    ]
)
