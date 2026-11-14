// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(path: "../SyntaxKit"),
        .package(path: "../Highlighting"),
    ]
)
