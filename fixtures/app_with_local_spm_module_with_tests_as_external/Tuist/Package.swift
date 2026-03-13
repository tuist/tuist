// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["LocalSwiftPackage": .framework]
    )
#endif

let package = Package(
    name: "App",
    dependencies: [
        .package(path: "../LocalSwiftPackage"),
    ]
)
