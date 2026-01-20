// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "App",
    dependencies: [
        .package(
            url: "https://github.com/EsotericSoftware/spine-runtimes",
            revision: "33cf98b4677e1ee51e60ed0020b41b783e7fc01f"
        ),
    ]
)
