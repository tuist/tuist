import ProjectDescription

let project = Project(
    name: "BundleMacro",
    targets: [
        .target(
            name: "ResourceLoader",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "dev.tuist.ResourceLoader",
            deploymentTargets: .macOS("14.0"),
            sources: "ResourceLoader/Sources/**"
        ),
        .target(
            name: "StaticFramework",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "dev.tuist.StaticFramework",
            deploymentTargets: .macOS("14.0"),
            sources: "StaticFramework/Sources/**",
            resources: ["StaticFramework/Resources/**"],
            dependencies: [
                .target(name: "ResourceLoader"),
            ]
        ),
        .target(
            name: "StaticFrameworkTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.StaticFrameworkTests",
            deploymentTargets: .macOS("14.0"),
            sources: "StaticFrameworkTests/Sources/**",
            dependencies: [
                .target(name: "StaticFramework"),
            ]
        ),
        .target(
            name: "App",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.App",
            deploymentTargets: .macOS("14.0"),
            sources: "App/Sources/**",
            dependencies: [
                .target(name: "StaticFramework"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            deploymentTargets: .macOS("14.0"),
            sources: "AppTests/Sources/**",
            dependencies: [
                .target(name: "App"),
                .target(name: "StaticFramework"),
            ]
        ),
    ]
)
