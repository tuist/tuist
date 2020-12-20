import ProjectDescription

let project = Project(
    name: "MainApp",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Config/App-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "Framework1-iOS", path: "../Framework1"),
            ]
        ),
        Target(
            name: "AppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: "Config/AppTests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
        Target(
            name: "AppUITests",
            platform: .iOS,
            product: .uiTests,
            bundleId: "io.tuist.AppUITests",
            infoPlist: "Config/AppTests-Info.plist",
            sources: "UITests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
