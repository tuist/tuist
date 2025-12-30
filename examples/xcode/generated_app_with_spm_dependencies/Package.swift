// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.8.0"),
        .package(url: "https://github.com/Quick/Nimble", exact: "13.2.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "10.21.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", exact: "8.26.0"),
    ]
)
