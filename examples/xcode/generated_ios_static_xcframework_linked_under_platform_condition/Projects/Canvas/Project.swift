import ProjectDescription

let project = Project(
    name: "Canvas",
    targets: [
        .target(
            name: "Canvas",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.Canvas",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/**"],
            dependencies: [
                .external(name: "NativeRendererKit"),
            ]
        ),
    ]
)
