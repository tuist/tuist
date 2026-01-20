// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        // Can use any version up to next major (i.e. 5.0.1, 5.6.0)
        .package(url: "https://github.com/SnapKit/SnapKit.git", from: "5.0.0"),
    ]
)
