import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: [
        .package(url: "https://github.com/Alamofire/Alamofire", .upToNextMajor(from: "5.0.0")),
        .package(url: "https://github.com/danielgindi/Charts", .upToNextMajor(from: "4.0.0")),
        .package(url: "https://github.com/facebook/facebook-ios-sdk", .upToNextMajor(from: "12.1.0")),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", .upToNextMajor(from: "8.0.0")),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "0.22.0")),
    ],
    platforms: [.iOS]
)
