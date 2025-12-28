import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.appleTv],
            product: .app,
            bundleId: "dev.tuist.App",
            deploymentTargets: .tvOS("14.0"),
            infoPlist: .default,
            sources: .paths([.relativeToManifest("App/Sources/**")])
        ),
        .target(
            name: "AppUITests",
            destinations: [.appleTv],
            product: .uiTests,
            bundleId: "dev.tuist.AppUITests",
            infoPlist: "UITests.plist",
            sources: "App/UITests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
