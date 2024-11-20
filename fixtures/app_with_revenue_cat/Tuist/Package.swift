// swift-tools-version: 6.0
@preconcurrency import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        targetSettings: [
            "RevenueCat": .settings(base: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited)"]),
        ]
    )
#endif

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios", .upToNextMajor(from: "5.0.0")),
    ]
)
