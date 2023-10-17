// swift-tools-version:5.7
import ProjectDescription
import ProjectDescriptionHelpers

let packages: [Package] = [
    .package(url: "https://github.com/Alamofire/Alamofire", .upToNextMajor(from: "5.8.0")),
    .package(url: "https://github.com/facebook/facebook-ios-sdk", .upToNextMajor(from: "16.1.3")),
    .package(url: "https://github.com/firebase/firebase-ios-sdk", .upToNextMajor(from: "10.15.0")),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "1.0.0")),
    .package(url: "https://github.com/iterable/swift-sdk", .upToNextMajor(from: "6.4.15")),
    .package(url: "https://github.com/Trendyol/ios-components", .revision("c9260bfe203a16a278eca5542c98455eece98aa4")),
    .package(url: "https://github.com/stripe/stripe-ios", .upToNextMajor(from: "23.12.0")),
    .local(path: "LocalSwiftPackage"),
    .package(url: "https://github.com/groue/GRDB.swift", .upToNextMajor(from: "6.16.0")),
    .local(path: "StringifyMacro"),
]

let dependencies = Dependencies(
    swiftPackageManager: .init(
        manifest: "Package.swift",
        baseSettings: .targetSettings,
        projectOptions: [
            "LocalSwiftPackage": .options(disableSynthesizedResourceAccessors: false),
        ]
    ),
    platforms: [.iOS, .watchOS]
)
