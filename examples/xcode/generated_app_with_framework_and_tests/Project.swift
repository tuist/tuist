import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app",
            infoPlist: "Info.plist",
            sources: "App/**",
            dependencies: [
                .target(name: "Framework"),
                .target(name: "AppExtension"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.appTests",
            infoPlist: "Info.plist",
            sources: "AppTests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
        .target(
            name: "AppExtension",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "dev.tuist.app.extension",
            infoPlist: "AppExtension/Info.plist",
            sources: "AppExtension/**",
            dependencies: [
                .target(name: "Framework"),
            ]
        ),
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.framework",
            infoPlist: "Info.plist",
            sources: "Framework/**",
            dependencies: [
            ]
        ),
        .target(
            name: "FrameworkTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.frameworkTests",
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
