import ProjectDescription

let project = Project(
    name: "App",
    settings: .settings(
        configurations: [
            .debug(name: "CustomDebug"),
            .debug(name: "AnotherDebug"),
            .release(name: "CustomRelease"),
            .release(name: "AnotherRelease"),
        ],
        defaultConfiguration: "CustomDebug"
    ),
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                ]
            ),
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"],
            dependencies: [
                .target(name: "Framework"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: .default,
            sources: ["App/Tests/**"],
            resources: [],
            dependencies: [.target(name: "App")]
        ),
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.framework",
            sources: ["Framework/Sources/**"]
        ),
    ]
)
