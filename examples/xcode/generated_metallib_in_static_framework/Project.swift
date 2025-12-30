import ProjectDescription

let project = Project(
    name: "StaticMetallibFramework",
    targets: [
        .target(
            name: "StaticMetallibFramework",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "dev.tuist.StaticMetallibFramework",
            sources: ["StaticMetallibFramework/Sources/**"],
            dependencies: []
        ),
    ]
)
