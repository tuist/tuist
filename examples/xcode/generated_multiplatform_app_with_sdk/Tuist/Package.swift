// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "11.2.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ]
)
