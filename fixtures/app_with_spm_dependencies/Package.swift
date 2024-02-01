// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        baseSettings: .targetSettings,
        projectOptions: [
            "LocalSwiftPackage": .options(disableSynthesizedResourceAccessors: false),
        ],
        platforms: [.iOS, .watchOS]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "1.5.0")),
        .package(path: "LocalSwiftPackage"),
        .package(path: "StringifyMacro"),
    ]
)
