import ProjectDescription

let project = Project(
    name: "StaticFramework4",
    targets: [
        .target(
            name: "StaticFramework4",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.StaticFramework4",
            infoPlist: .default,
            sources: "Sources/**",
            resources: "Resources/**",
            dependencies: [
            ]
        ),
    ]
)
