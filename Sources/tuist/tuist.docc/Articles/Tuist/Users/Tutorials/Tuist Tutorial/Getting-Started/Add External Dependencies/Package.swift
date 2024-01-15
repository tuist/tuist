// swift-tools-version: 5.8
import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "Alamofire": .framework, // default is .staticFramework
    ],
    platforms: [.iOS]
)
#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ]
)
