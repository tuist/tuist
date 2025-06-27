import ProjectDescription

let project = Project(
    name: "SharedUI",
    targets: [
        .target(
            name: "SharedUI",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("16.0"),
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
                .external(name: "Stripe"),
            ]
        ),
    ]
)
