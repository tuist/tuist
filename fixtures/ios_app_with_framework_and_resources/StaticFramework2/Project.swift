import ProjectDescription

let project = Project(
    name: "StaticFramework2",
    targets: [
        .target(
            name: "StaticFramework2",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework2",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
                .target(name: "StaticFramework2Resources"),
            ]
        ),
        .target(
            name: "StaticFramework2Resources",
            destinations: .iOS,
            product: .bundle,
            bundleId: "io.tuist.StaticFramework2Resources",
            infoPlist: .default,
            sources: [],
            resources: "Resources/**",
            dependencies: []
        ),
    ]
)
