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
            bundleId: "io.tuist.App",
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
            bundleId: "io.tuist.AppTests",
            infoPlist: .default,
            sources: ["App/Tests/**"],
            resources: [],
            dependencies: [.target(name: "App")]
        ),
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.framework",
            sources: ["Framework/Sources/**"]
        ),
    ]
)
