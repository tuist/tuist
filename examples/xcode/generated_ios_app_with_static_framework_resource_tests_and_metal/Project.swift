import ProjectDescription

let project = Project(
    name: "StaticFrameworkResourceTestsAndMetal",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app",
            infoPlist: .default,
            sources: "App/**",
            dependencies: [
                .target(name: "StaticResourcesFramework"),
                .target(name: "StaticMetalFramework"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.appTests",
            infoPlist: .default,
            sources: "AppTests/**",
            dependencies: [
                .target(name: "StaticResourcesFramework"),
                .target(name: "App"),
            ]
        ),
        .target(
            name: "StaticResourcesFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.staticResourcesFramework",
            sources: "StaticResourcesFramework/Sources/**",
            resources: "StaticResourcesFramework/Resources/**",
            dependencies: []
        ),
        .target(
            name: "StaticMetalFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.staticMetalFramework",
            sources: "StaticMetalFramework/Sources/**",
            dependencies: []
        ),
    ]
)
