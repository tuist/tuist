import ProjectDescription

let project = Project(
    name: "StaticFramework",
    options: .options(
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    targets: [
        .target(
            name: "StaticFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.StaticFramework",
            infoPlist: "Config/StaticFramework-Info.plist",
            sources: "Sources/**",
            dependencies: []
        ),
        .target(
            name: "StaticFrameworkResources",
            destinations: .iOS,
            product: .bundle,
            bundleId: "dev.tuist.StaticFrameworkResources",
            infoPlist: .default,
            sources: [],
            resources: "Resources/**",
            dependencies: []
        ),
    ]
)
