// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.8.0"),
        .package(url: "https://github.com/facebook/facebook-ios-sdk", from: "16.1.3"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.15.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "1.0.0")),
        .package(url: "https://github.com/iterable/swift-sdk", from: "6.4.15"),
        .package(url: "https://github.com/Trendyol/ios-components", revision: "c9260bfe203a16a278eca5542c98455eece98aa4"),
        .package(url: "https://github.com/stripe/stripe-ios", from: "23.12.0"),
        .package(path: "../../../LocalSwiftPackage"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.16.0"),
        .package(path: "../../../StringifyMacro"),
    ]
)