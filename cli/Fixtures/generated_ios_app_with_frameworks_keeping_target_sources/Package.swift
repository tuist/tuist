// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(productTypes: ["GoogleUtilities-NSData": .framework])
#endif
let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/google/GoogleUtilities", from: "8.1.0"),
    ]
)
