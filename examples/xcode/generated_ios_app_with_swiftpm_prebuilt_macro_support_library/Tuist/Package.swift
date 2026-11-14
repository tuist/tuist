// swift-tools-version: 6.2
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        productTypes: ["CasePathsMacrosSupport": .staticFramework]
    )
#endif

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-navigation", exact: "2.10.2"),
        .package(url: "https://github.com/swiftlang/swift-syntax", exact: "602.0.0"),
    ]
)
