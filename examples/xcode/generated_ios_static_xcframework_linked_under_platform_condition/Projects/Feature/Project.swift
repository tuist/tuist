import ProjectDescription

let project = Project(
    name: "Feature",
    targets: [
        .target(
            name: "Feature",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.Feature",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/**"],
            dependencies: [
                .project(target: "Palette", path: "../Palette"),
                .project(target: "Canvas", path: "../Canvas"),
            ]
        ),
    ]
)
