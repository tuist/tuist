import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "MyTarget",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.MyTarget",
            infoPlist: .default,
            sources: [
                "MyTarget/Sources/**",
            ],
            resources: [
            ],
            dependencies: [
                .xcframework(path: "Frameworks/MyFramework.xcframework"),
            ]
        ),
    ]
)
