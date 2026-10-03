import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.BundleIdentifiers",
            deploymentTargets: .iOS("15.0"),
            infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
            sources: ["Sources/**"],
            dependencies: [.external(name: "IssueReporting")]
        ),
    ]
)
