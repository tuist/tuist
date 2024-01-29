import ProjectDescription

let project = Project(
    name: "StaticFramework",
    targets: [
        .target(
            name: "StaticFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework",
            infoPlist: "Config/StaticFramework-Info.plist",
            sources: "Sources/**",
            dependencies: []
        ),
        .target(
            name: "StaticFrameworkResources",
            destinations: .iOS,
            product: .bundle,
            bundleId: "io.tuist.StaticFrameworkResources",
            infoPlist: .default,
            sources: [],
            resources: "Resources/**",
            dependencies: []
        ),
    ]
)
