// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        // Has space symbols in package name
        .package(url: "https://github.com/Shopify/mobile-buy-sdk-ios", exact: "12.0.0"),
        // Has targets with slash symbols in their names
        .package(url: "https://github.com/kstenerud/KSCrash", exact: "1.17.1"),
        // Has custom `swiftSettings` and uses the package access level
        .package(url: "https://github.com/vapor/jwt-kit.git", .upToNextMajor(from: "5.0.0-beta.2.1")),
    ]
)
