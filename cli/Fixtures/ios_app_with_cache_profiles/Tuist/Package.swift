// swift-tools-version: 6.0
@preconcurrency import PackageDescription

let package = Package(
    name: "CacheProfilesExternalDeps",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ]
)
