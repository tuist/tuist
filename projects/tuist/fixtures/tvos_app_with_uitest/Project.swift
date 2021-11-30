import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .tvOS,
            product: .app,
            bundleId: "io.tuist.App",
            deploymentTarget: .tvOS(targetVersion: "14.0"),
            infoPlist: .default,
            sources: .paths([.relativeToManifest("App/Sources/**")])
        ),
        Target(
            name: "AppUITests",
            platform: .tvOS,
            product: .uiTests,
            bundleId: "io.tuist.AppUITests",
            infoPlist: "UITests.plist",
            sources: "App/UITests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
