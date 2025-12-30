import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["App/Sources/**"],
            dependencies: [
                .target(name: "DynamicFramework"),
            ]
        ),
        .target(
            name: "DynamicFramework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.DynamicFramework",
            sources: ["DynamicFramework/Sources/**"],
            dependencies: [
                .external(name: "GoogleMaps"),
                .external(name: "GoogleMapsBase"),
                .external(name: "GoogleMapsCore"),
            ]
        ),
    ]
)
