// swift-tools-version: 6.0
@preconcurrency import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: ["PocketSVG": .framework]
    )
#endif

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/pocketsvg/PocketSVG", exact: "2.7.3"),
    ]
)
