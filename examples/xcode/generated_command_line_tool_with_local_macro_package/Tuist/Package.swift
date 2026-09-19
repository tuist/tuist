// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    baseSettings: .settings(
        base: [
            "OTHER_SWIFT_FLAGS": ["-Xfrontend -disable-sil-ownership-verifier"],
        ]
    )
)
#endif

let package = Package(
    name: "Dependencies",
    dependencies: [
        .package(path: "../Package"),
    ]
)
