// swift-tools-version: 5.10
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        productTypes: [
            "RuntimeLib": .staticFramework,
        ]
    )
#endif

let package = Package(
    name: "CommandLineToolDependencies",
    dependencies: [
        .package(path: "../RuntimePackage"),
    ]
)
