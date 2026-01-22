// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        productTypes: [:]
    )
#endif

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/apollographql/apollo-ios.git", exact: "1.7.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", exact: "0.15.5"),
    ]
)
