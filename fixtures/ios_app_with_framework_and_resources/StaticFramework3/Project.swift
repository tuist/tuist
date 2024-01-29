import ProjectDescription

let project = Project(
    name: "StaticFramework3",
    targets: [
        .target(
            name: "StaticFramework3",
            destinations: .iOS,
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
