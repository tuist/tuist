import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "dev.tuist.App",
            sources: ["Sources/**"],
            dependencies: [.external(name: "nanopb")]
        ),
    ]
)
