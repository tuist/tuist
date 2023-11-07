import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .visionOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Support/Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ]
        ),
        Target(
            name: "AppTests",
            platform: .visionOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: "Support/Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
