// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(productTypes: ["Shared": .staticFramework, "Leaf": .staticFramework])
#endif

let package = Package(
    name: "PlatformNarrowingDependencies",
    dependencies: [.package(path: "../LocalPackage")]
)
