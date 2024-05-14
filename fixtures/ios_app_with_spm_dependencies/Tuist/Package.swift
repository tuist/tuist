// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        // Has space symbols in package name
        .package(url: "https://github.com/Shopify/mobile-buy-sdk-ios", exact: "12.0.0"),
    ]
)
