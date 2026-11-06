import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.tuist.registry-spm-traits",
            sources: ["Sources/App"],
            dependencies: [
                .external(name: "Dependencies"),
            ]
        ),
    ]
)
