import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: "Info.plist",
            sources: "App/**",
            dependencies: [
                .target(name: "Framework"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.appTests",
            infoPlist: "Info.plist",
            sources: "AppTests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.framework",
            infoPlist: "Info.plist",
            sources: "Framework/**",
            dependencies: [
            ]
        ),
        .target(
            name: "FrameworkTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.frameworkTests",
            infoPlist: "Info.plist",
            sources: "FrameworkTests/**",
            dependencies: [
                .target(name: "Framework"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "AppCustomScheme",
            buildAction: .buildAction(targets: [TargetReference("App")])
        ),
    ]
)
