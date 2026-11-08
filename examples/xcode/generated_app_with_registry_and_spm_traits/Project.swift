import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["App/Sources"],
            dependencies: [
                .external(name: "Dependencies"),
            ]
        ),
    ]
)
