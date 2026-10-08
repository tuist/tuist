import ProjectDescription

let project = Project(
    name: "NetworkKit",
    targets: [
        .target(
            name: "NetworkKit",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.networkKit",
            sources: "Sources/**"
        ),
        .target(
            name: "NetworkKit-UnitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.networkKit.unitTests",
            sources: "UnitTests/**",
            dependencies: [
                .target(name: "NetworkKit"),
            ]
        ),
        .target(
            name: "NetworkKit-ScreenshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.networkKit.screenshotTests",
            sources: "ScreenshotTests/**",
            dependencies: [
                .target(name: "NetworkKit"),
            ],
            metadata: .metadata(tags: ["screenshot-tests"])
        ),
    ]
)
