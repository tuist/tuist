import ProjectDescription

let project = Project(
    name: "MainApp",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: "Config/App-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "Framework1-iOS", path: "../Framework1"),
                .project(target: "FrameworkA-iOS", path: "../FrameworkA"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: "Config/AppTests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
        .target(
            name: "AppUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "dev.tuist.AppUITests",
            infoPlist: "Config/AppTests-Info.plist",
            sources: "UITests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
