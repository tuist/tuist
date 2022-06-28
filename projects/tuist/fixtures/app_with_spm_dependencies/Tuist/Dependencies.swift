import ProjectDescription
import ProjectDescriptionHelpers

let dependencies = Dependencies(
    swiftPackageManager: .init(
        [
            .package(url: "https://github.com/Alamofire/Alamofire", .upToNextMajor(from: "5.6.0")),
            .package(url: "https://github.com/danielgindi/Charts", .upToNextMajor(from: "4.0.0")),
            .package(url: "https://github.com/facebook/facebook-ios-sdk", .upToNextMajor(from: "13.2.0")),
            .package(url: "https://github.com/firebase/firebase-ios-sdk", .upToNextMajor(from: "9.0.0")),
            .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "0.34.0")),
            .package(url: "https://github.com/iterable/swift-sdk", .upToNextMajor(from: "6.4.0")),
            .package(url: "https://github.com/Trendyol/ios-components", .revision("c9260bfe203a16a278eca5542c98455eece98aa4")),
            .package(url: "https://github.com/realm/realm-cocoa.git", .upToNextMajor(from: "10.24.0")),
            .package(url: "https://github.com/stripe/stripe-ios", .upToNextMajor(from: "22.4.0")),
            .local(path: "LocalSwiftPackage"),
        ],
        baseSettings: .settings(configurations: [
            .debug(name: .debug),
            .release(name: .release),
            .release(name: "Internal"),
        ]),
        projectOptions: [
            "LocalSwiftPackage": .options(disableSynthesizedResourceAccessors: false),
        ]
    ),
    platforms: [.iOS]
)
