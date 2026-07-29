// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SwifterPMNIODeps",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "0.4.0"),
        .package(url: "https://github.com/tuist/FileSystem.git", exact: "0.18.0"),
        .package(url: "https://github.com/tuist/Path.git", exact: "0.3.8"),
    ],
    targets: [
        .target(
            name: "SwifterPMNIODeps",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "FileSystem", package: "FileSystem"),
                .product(name: "Path", package: "Path"),
            ]
        ),
    ]
)
