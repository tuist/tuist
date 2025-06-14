import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .target(name: "FrameworkA"),
                .target(name: "FrameworkB"),
            ]
        ),
        .target(
            name: "FrameworkA",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.FrameworkA",
            sources: ["Targets/FrameworkA/Sources/**"]
        ),
        .target(
            name: "FrameworkB",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.FrameworkB",
            sources: ["Targets/FrameworkB/Sources/**"]
        ),
        .target(
            name: "FrameworkC",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.FrameworkC",
            sources: ["Targets/FrameworkC/Sources/**"],
            dependencies: [
                .target(name: "FrameworkB"),
            ]
        ),
    ]
)
