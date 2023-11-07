import ProjectDescription

let project = Project(
    name: "StaticFramework3",
    targets: [
        Target(
            name: "StaticFramework3",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework3",
            infoPlist: .default,
            sources: "Sources/**",
            resources: "Resources/**",
            dependencies: [
            ]
        ),
    ]
)
