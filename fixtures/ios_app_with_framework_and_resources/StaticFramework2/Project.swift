import ProjectDescription

let project = Project(
    name: "StaticFramework2",
    targets: [
        Target(
            name: "StaticFramework2",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework2",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
                .target(name: "StaticFramework2Resources"),
            ]
        ),
        Target(
            name: "StaticFramework2Resources",
            platform: .iOS,
            product: .bundle,
            bundleId: "io.tuist.StaticFramework2Resources",
            infoPlist: .default,
            sources: [],
            resources: "Resources/**",
            dependencies: []
        ),
    ]
)
