import ProjectDescription
import ProjectDescriptionHelpers

let packages: [Package] = [
    .package(url: "https://github.com/Alamofire/Alamofire", .upToNextMajor(from: "5.6.0")),
    .package(url: "https://github.com/facebook/facebook-ios-sdk", .upToNextMajor(from: "13.2.0")),
    .package(url: "https://github.com/firebase/firebase-ios-sdk", .upToNextMajor(from: "9.3.0")),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "0.40.0")),
    .package(url: "https://github.com/iterable/swift-sdk", .upToNextMajor(from: "6.4.0")),
    .package(url: "https://github.com/Trendyol/ios-components", .revision("c9260bfe203a16a278eca5542c98455eece98aa4")),
    .package(url: "https://github.com/stripe/stripe-ios", .upToNextMajor(from: "22.4.0")),
    .local(path: "LocalSwiftPackage"),
    .package(url: "https://github.com/groue/GRDB.swift", .upToNextMajor(from: "5.26.0")),
]

let dependencies = Dependencies(
    swiftPackageManager: .init(
        packages,
        baseSettings: .targetSettings,
        projectOptions: [
            "LocalSwiftPackage": .options(disableSynthesizedResourceAccessors: false),
        ]
    ),
    platforms: [.iOS, .watchOS]
)
