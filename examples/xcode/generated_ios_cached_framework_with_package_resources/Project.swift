import ProjectDescription

let project = Project(
    name: "CachedFrameworkWithPackageResources",
    targets: [
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework",
            deploymentTargets: .iOS("16.0"),
            sources: "Framework/Sources/**",
            dependencies: [
                .external(name: "ResourcesLib"),
            ]
        ),
        .target(
            name: "FrameworkTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.FrameworkTests",
            deploymentTargets: .iOS("16.0"),
            sources: "FrameworkTests/Sources/**",
            dependencies: [
                .target(name: "Framework"),
                .external(name: "ResourcesLib"),
            ]
        ),
    ]
)
