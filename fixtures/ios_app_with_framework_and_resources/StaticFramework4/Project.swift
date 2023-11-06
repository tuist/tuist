import ProjectDescription

let project = Project(
    name: "StaticFramework4",
    targets: [
        Target(
            name: "StaticFramework4",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework4",
            infoPlist: .default,
            sources: "Sources/**",
            resources: "Resources/**",
            dependencies: [
            ]
        ),
    ]
)
