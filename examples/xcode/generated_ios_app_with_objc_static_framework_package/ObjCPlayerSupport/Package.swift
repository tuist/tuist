// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "ObjCPlayerSupport",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "ObjCPlayerSupport",
            targets: ["ObjCPlayerSupport"]
        ),
    ],
    targets: [
        .target(
            name: "ObjCPlayerSupport",
            publicHeadersPath: "."
        ),
    ]
)
