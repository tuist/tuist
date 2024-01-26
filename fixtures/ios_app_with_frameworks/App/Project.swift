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
            bundleId: "io.tuist.App",
            infoPlist: .extendingDefault(with: [:]),
            sources: "Sources/**",
            resources: "Sources/Main.storyboard",
            dependencies: [
                .project(target: "Framework1", path: "../Framework1"),
                .project(target: "Framework2-iOS", path: "../Framework2"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: .extendingDefault(with: [:]),
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
