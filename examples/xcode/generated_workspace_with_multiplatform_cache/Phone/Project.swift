import ProjectDescription

let project = Project(
    name: "Phone",
    settings: .settings(base: ["CODE_SIGNING_ALLOWED": "NO"]),
    targets: [.target(
        name: "PhoneConsumer",
        destinations: [.iPhone, .iPad, .macWithiPadDesign],
        product: .framework,
        bundleId: "dev.tuist.fixture.phone",
        deploymentTargets: .iOS("16.0"),
        infoPlist: .default,
        sources: ["Phone.swift"],
        dependencies: [.external(name: "Shared")]
    )]
)
