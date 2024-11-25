// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        baseSettings: .settings(
            base: [
                "ENABLE_USER_SCRIPT_SANDBOXING": true,
            ]
        )
    )

#endif

let package = Package(
    name: "Dependencies",
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.5.6"),
        .package(url: "https://github.com/apple/swift-syntax", "510.0.3" ..< "601.0.0-prerelease"),
    ]
)
