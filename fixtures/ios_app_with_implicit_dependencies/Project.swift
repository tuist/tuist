import ProjectDescription

let project =  Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        Target(
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
        Target(
            name: "FrameworkA",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.FrameworkA",
            sources: ["Targets/FrameworkA/Sources/**"]
        ),
        Target(
            name: "FrameworkB",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.FrameworkB",
            sources: ["Targets/FrameworkB/Sources/**"]
        ),
        Target(
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
