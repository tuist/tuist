import ProjectDescription

let settings: Settings = .settings(base: [
    "HEADER_SEARCH_PATHS": "path/to/lib/include",
])
let project = Project(
    name: "MainApp",
    settings: settings,
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
    ]
)
