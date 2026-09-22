import ProjectDescription

let project = Project(
    name: "Services",
    targets: [
        .target(
            name: "Services",
            destinations: [.iPhone],
            product: .staticFramework,
            bundleId: "dev.tuist.Services",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/**"]
        ),
    ]
)
