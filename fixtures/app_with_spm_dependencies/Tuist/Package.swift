// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "1.5.0")),
        .package(path: "../../../LocalSwiftPackage"),
        .package(path: "../../../StringifyMacro"),
    ]
)
