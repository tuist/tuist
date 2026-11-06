// swift-tools-version: 6.0
@preconcurrency import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(path: "../ResourcesPackage"),
    ]
)
