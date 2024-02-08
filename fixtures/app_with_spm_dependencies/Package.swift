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
        // .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.8.0"),
        // .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "1.5.0")),
        .package(url: "https://github.com/ZipArchive/ZipArchive", .upToNextMajor(from: "2.5.5")),
        .package(url: "https://github.com/jpsim/Yams", .upToNextMajor(from: "5.0.6")),
        // .package(url: "https://github.com/google/GoogleSignIn-iOS", .upToNextMajor(from: "7.0.0")),
        // .package(path: "LocalSwiftPackage"),
        // .package(path: "StringifyMacro"),
    ]
)
