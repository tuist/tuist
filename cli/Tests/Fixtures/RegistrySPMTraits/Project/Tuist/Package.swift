// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Dependencies",
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies",
            from: "1.14.1",
            traits: [
                "Clocks",
                "CombineSchedulers",
                "Foundation",
                "FoundationNetworking",
            ]
        ),
    ]
)
