// swift-tools-version:5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalSwiftPackage",
    defaultLocalization: "en",
    platforms: [.iOS(.v13)],
    products: [.library(name: "Styles", targets: ["Styles"]), .library(name: "TestsSupport", targets: ["TestsSupport"])],
    // dependencies: [.alamofireLibrary],
    targets: [
        .target(
            name: "Styles",
            resources: [
                .process("Resources/Fonts"),
                .copy("Resources/jsonFile.json"), // copy rule, single file
                .copy("Resources/Playground.playground"), // copy rule, opaque file
                .copy("Resources/www"), // copy rule, directory
            ]
        ),
        .target(
            name: "TestsSupport",
            dependencies: [ /* .productItem(name: "Alamofire", package: "Alamofire") */ ]
        ),
        .testTarget(
            name: "StylesTests",
            dependencies: ["TestsSupport", "Styles"].map {
                Target.Dependency(stringLiteral: $0)
            }
        ),
    ]
)

extension Package.Dependency {
    // static let alamofireLibrary: Package.Dependency = .package(url: "https://github.com/Alamofire/Alamofire",
    // .upToNextMajor(from: "5.6.0"))
}
