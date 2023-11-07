// swift-tools-version:5.7
import ProjectDescription
import ProjectDescriptionHelpers

let dependencies = Dependencies(
    swiftPackageManager: .init(
        baseSettings: .targetSettings,
        projectOptions: [
            "LocalSwiftPackage": .options(disableSynthesizedResourceAccessors: false),
        ]
    ),
    platforms: [.iOS, .watchOS]
)
