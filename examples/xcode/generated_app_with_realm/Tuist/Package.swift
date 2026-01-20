// swift-tools-version: 5.10
@preconcurrency import PackageDescription

#if TUIST
    @preconcurrency import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
    )
#endif

let package = Package(
    name: "App",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/realm/realm-swift", .upToNextMajor(from: "10.46.0")),
    ]
)
