import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init(
        [
            .package(url: "https://github.com/danielgindi/Charts", .upToNextMajor(from: "4.0.0")),
            .package(url: "https://github.com/adjust/ios_sdk/", .upToNextMajor(from: "4.0.0")),
            .package(url: "https://github.com/facebook/facebook-ios-sdk", .upToNextMajor(from: "11.0.0")),
            .package(url: "https://github.com/firebase/firebase-ios-sdk", .upToNextMajor(from: "8.0.0")),
            .package(url: "https://github.com/Alamofire/Alamofire", .upToNextMajor(from: "5.0.0")),
            .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "0.22.0")),
            .package(url: "https://github.com/Quick/Quick", .upToNextMajor(from: "4.0.0")),
            .package(url: "https://github.com/Quick/Nimble", .upToNextMajor(from: "9.0.0")),
            .package(url: "https://github.com/Trendyol/ios-components", .branch("master"))
        ],
        deploymentTargets: [.iOS(targetVersion: "9.0", devices: [.iphone])]
    ),
    platforms: [.iOS]
)
