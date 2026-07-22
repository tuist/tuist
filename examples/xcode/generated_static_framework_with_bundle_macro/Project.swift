import ProjectDescription

let project = Project(
    name: "BundleMacro",
    targets: [
        .target(
            name: "ResourceLoader",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.ResourceLoader",
            deploymentTargets: .iOS("16.0"),
            sources: "ResourceLoader/Sources/**"
        ),
        .target(
            name: "StaticFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.StaticFramework",
            deploymentTargets: .iOS("16.0"),
            sources: "StaticFramework/Sources/**",
            resources: ["StaticFramework/Resources/**"],
            dependencies: [
                .target(name: "ResourceLoader"),
            ]
        ),
        .target(
            name: "StaticFrameworkTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.StaticFrameworkTests",
            deploymentTargets: .iOS("16.0"),
            sources: "StaticFrameworkTests/Sources/**",
            dependencies: [
                .target(name: "StaticFramework"),
            ]
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            deploymentTargets: .iOS("16.0"),
            sources: "App/Sources/**",
            dependencies: [
                .target(name: "StaticFramework"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            deploymentTargets: .iOS("16.0"),
            sources: "AppTests/Sources/**",
            dependencies: [
                .target(name: "App"),
                .target(name: "StaticFramework"),
            ]
        ),
    ]
)
