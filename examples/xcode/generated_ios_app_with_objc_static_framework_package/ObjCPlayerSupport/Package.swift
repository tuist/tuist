// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "ObjCPlayer-Support",
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
            resources: [.process("Resources")],
            publicHeadersPath: "."
        ),
    ]
)
