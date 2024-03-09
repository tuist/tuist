// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MyLocalPackage",
    products: [.library(name: "MyLibrary", targets: ["MyLibrary"])],
    targets: [
        .target(
            name: "MyLibrary",
            dependencies: [
                .byName(name: "Alamofire"),
            ]
        ),
    ]
)
