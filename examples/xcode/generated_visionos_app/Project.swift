import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.appleVision],
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: "Support/Info.plist",
            sources: ["Sources/**"],
            resources: [
                // Path to resources can be defined here
                // "Resources/**"
            ]
        ),
        .target(
            name: "AppTests",
            destinations: [.appleVision],
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: "Support/Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
        .target(
            name: "AppUITests",
            destinations: [.appleVision],
            product: .uiTests,
            bundleId: "dev.tuist.AppUITests",
            infoPlist: "Support/UITests.plist",
            sources: "UITests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
