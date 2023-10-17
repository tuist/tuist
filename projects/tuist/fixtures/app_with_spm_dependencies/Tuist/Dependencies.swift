// swift-tools-version:5.7
import ProjectDescription
import ProjectDescriptionHelpers

let dependencies = Dependencies(
    swiftPackageManager: .init(
        manifest: "Tuist/Package.swift",
        baseSettings: .targetSettings,
        projectOptions: [
            "LocalSwiftPackage": .options(disableSynthesizedResourceAccessors: false),
        ]
    ),
    platforms: [.iOS, .watchOS]
)
