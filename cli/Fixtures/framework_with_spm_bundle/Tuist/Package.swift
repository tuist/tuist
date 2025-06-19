// swift-tools-version: 5.10
@preconcurrency import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/stripe/stripe-ios-spm", exact: "23.27.3"),
    ]
)
