import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.tuist.issue12338",
            sources: ["Sources/App"],
            dependencies: [
                .external(name: "Dependencies"),
            ]
        ),
    ]
)
