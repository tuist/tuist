// swift-tools-version: 5.9

@preconcurrency import PackageDescription

let package = Package(
    name: "project_with_previews_crash",
    dependencies: [
        .package(path: "../ResourcesFramework"),
    ]
)
