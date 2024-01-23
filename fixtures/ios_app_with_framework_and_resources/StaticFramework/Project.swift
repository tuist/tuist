import ProjectDescription

let project = Project(
    name: "StaticFramework",
    targets: [
        Target(
            name: "StaticFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework",
            infoPlist: "Config/StaticFramework-Info.plist",
            sources: "Sources/**",
            dependencies: []
        ),
        Target(
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
