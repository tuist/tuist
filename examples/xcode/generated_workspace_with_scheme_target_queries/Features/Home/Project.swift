import ProjectDescription

let project = Project(
    name: "HomeFeature",
    targets: [
        .target(
            name: "HomeFeature",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.homeFeature",
            sources: "Sources/**"
        ),
        .target(
            name: "HomeFeature-UnitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.homeFeature.unitTests",
            sources: "UnitTests/**",
            dependencies: [
                .target(name: "HomeFeature"),
            ]
        ),
        .target(
            name: "HomeFeature-ScreenshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.homeFeature.screenshotTests",
            sources: "ScreenshotTests/**",
            dependencies: [
                .target(name: "HomeFeature"),
            ],
            metadata: .metadata(tags: ["screenshot-tests"])
        ),
    ]
)
