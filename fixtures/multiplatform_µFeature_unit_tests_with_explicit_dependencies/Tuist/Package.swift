// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
         productTypes: [ // Convert 3rd party frameworks into dynamic frameworks
            "Mocker": .framework,
        ]
    )
#endif

let package = Package(
    name: "Dependencies",
    dependencies: [
        .package(url: "https://github.com/WeTransfer/Mocker", revision: "3.0.1"),
    ]
)
