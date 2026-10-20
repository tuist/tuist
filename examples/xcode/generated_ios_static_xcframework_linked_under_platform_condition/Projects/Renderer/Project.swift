import ProjectDescription

let project = Project(
    name: "Renderer",
    targets: [
        .target(
            name: "Renderer",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Renderer",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/**"],
            dependencies: [
                .external(name: "NativeRendererKit"),
            ]
        ),
    ]
)
