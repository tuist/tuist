import ProjectDescription

let project = Project(
    name: "MainApp",
    options: .options(
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Config/App-Info.plist",
            sources: "Sources/**",
            resources: [
                "Resources/**/*.png",
                "Resources/*.xcassets",
            ],
            dependencies: [
                .project(target: "Framework1", path: "../Framework1"),
                .project(target: "StaticFramework", path: "../StaticFramework"),
            ]
        ),
    ]
)
