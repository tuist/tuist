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
        .package(url: "https://github.com/Quick/Quick.git", .upToNextMajor(from: "7.6.0")),
        .package(url: "https://github.com/Quick/Nimble.git", .upToNextMajor(from: "13.8.0")),
    ]
)
