import ProjectDescription

let project = Project(
    name: "StaticFramework5",
    targets: [
        Target(
            name: "StaticFramework5",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework5",
            infoPlist: .default,
            resources: "Resources/**",
            dependencies: [
            ]
        ),
    ]
)
