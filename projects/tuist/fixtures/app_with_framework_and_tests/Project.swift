import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: "Info.plist",
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
            infoPlist: "Info.plist",
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
            infoPlist: "Info.plist",
            sources: "Framework/**",
            dependencies: [
            ]
        ),
        Target(
            name: "FrameworkTests",
            platform: .iOS,
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
        Scheme(
            name: "AppCustomScheme",
            buildAction: .buildAction(targets: [TargetReference("App")])
        ),
    ]
)
