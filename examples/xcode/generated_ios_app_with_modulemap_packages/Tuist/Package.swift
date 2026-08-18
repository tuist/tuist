// swift-tools-version: 6.2
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(baseProductType: .framework)
#endif

let package = Package(
    name: "ModuleMapPackages",
    dependencies: [
        .package(url: "https://github.com/1024jp/GzipSwift", exact: "6.0.0"),
        .package(url: "https://github.com/GEOSwift/GEOSwift", exact: "11.2.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "12.6.0"),
    ]
)
