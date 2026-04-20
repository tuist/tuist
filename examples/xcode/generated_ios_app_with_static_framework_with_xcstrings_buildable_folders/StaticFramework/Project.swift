import ProjectDescription

let project = Project(
    name: "StaticFramework",
    targets: [
        .target(
            name: "StaticFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.StaticFramework",
            deploymentTargets: .iOS("16.0"),
            buildableFolders: [
                "Sources",
                "Resources",
            ]
        ),
    ]
)
