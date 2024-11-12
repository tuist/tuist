// swift-tools-version: 6.0
@preconcurrency import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: ["ComposableArchitecture": .framework]
    )
#endif

let package = Package(
    name: "App",
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            .upToNextMinor(from: "1.15.2"))
    ]
)
