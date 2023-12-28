// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", exact: "7.0.0")
    ]
)
