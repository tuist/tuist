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
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-syntax", "509.0.0" ..< "601.0.0-prerelease"),
    ]
)
