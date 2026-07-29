// swift-tools-version: 6.2
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(productTypes: [:])
#endif

let package = Package(
    name: "App",
    dependencies: [
        .package(path: "../MacroDependency"),
    ]
)
