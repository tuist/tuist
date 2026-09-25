import ProjectDescription

let project = Project(
    name: "Tokens",
    targets: [
        .target(
            name: "Tokens",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.Tokens",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/**"],
            dependencies: []
        ),
    ]
)
