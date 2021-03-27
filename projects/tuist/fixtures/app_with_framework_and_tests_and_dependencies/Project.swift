import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: .default,
            sources: "App/**",
            dependencies: [
                .target(name: "Framework"),
            ]
        ),
        Target(
            name: "AppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.appTests",
            infoPlist: .default,
            sources: "AppTests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
        Target(
            name: "Framework",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.framework",
            infoPlist: .default,
            sources: "Framework/**",
            dependencies: [
            ]
        ),
        Target(
            name: "FrameworkTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.frameworkTests",
            infoPlist: .default,
            sources: "FrameworkTests/**",
            dependencies: [
                .target(name: "Framework"),
            ]
        ),
    ],
    schemes: [
        Scheme(
            name: "AppCustomScheme",
            buildAction: BuildAction(targets: [TargetReference("App")])
        )
    ]
)
