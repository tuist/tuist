import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init(
        [
            .package(url: "https://github.com/adjust/ios_sdk/", .upToNextMajor(from: "4.0.0")),
            .package(url: "https://github.com/Alamofire/Alamofire", .upToNextMajor(from: "5.0.0")),
            .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "0.22.0")),
            .package(url: "https://github.com/Quick/Quick", .upToNextMajor(from: "4.0.0")),
            .package(url: "https://github.com/Quick/Nimble", .upToNextMajor(from: "9.0.0")),
        ],
        deploymentTargets: [.iOS(targetVersion: "9.0", devices: [.iphone])]
    ),
    platforms: [.iOS]
)
