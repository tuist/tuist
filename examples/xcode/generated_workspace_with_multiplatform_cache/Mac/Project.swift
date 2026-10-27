import ProjectDescription

let project = Project(
    name: "Mac",
    settings: .settings(base: ["CODE_SIGNING_ALLOWED": "NO"]),
    targets: [.target(
        name: "MacConsumer",
        destinations: [.mac],
        product: .commandLineTool,
        bundleId: "dev.tuist.fixture.mac",
        deploymentTargets: .macOS("13.0"),
        sources: ["main.swift"],
        dependencies: [.external(name: "Shared")]
    )]
)
