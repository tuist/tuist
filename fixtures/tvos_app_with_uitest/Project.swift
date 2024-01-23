import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            destinations: [.appleTv],
            product: .app,
            bundleId: "io.tuist.App",
            deploymentTarget: .tvOS(targetVersion: "14.0"),
            infoPlist: .default,
            sources: .paths([.relativeToManifest("App/Sources/**")])
        ),
        Target(
            name: "AppUITests",
            destinations: [.appleTv],
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
