// swift-tools-version: 6.2
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:],
        productTraits: [
            "Package": ["Tuist"],
        ]
    )
#endif

let package = Package(
    name: "App",
    dependencies: [
        .package(path: "../Package", traits: [.trait(name: "Tuist")]),
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
    ]
)
