// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dependencies",
    dependencies: [
        .package(path: "../NativeRendererPackage"),
    ]
)
