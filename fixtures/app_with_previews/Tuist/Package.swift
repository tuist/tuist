// swift-tools-version: 5.9

import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productDestinations: [
            "ResourcesFramework": [
                .iPad,
                .iPhone,
                .macCatalyst,
            ],
        ]
    )
#endif

let package = Package(
    name: "project_with_previews_crash",
    dependencies: [
        .package(path: "../ResourcesFramework"),
    ]
)
