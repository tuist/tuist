import ProjectDescription

let project = Project(
    name: "App",
    settings: .settings(
        base: [
            "SWIFT_UPCOMING_FEATURE_INTERNAL_IMPORTS_BY_DEFAULT": .string("YES"),
        ]
    ),
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("17.0.0"),
            infoPlist: .default,
            buildableFolders: [
                "App/Sources",
            ],
            dependencies: [
                .target(name: "Framework"),
            ]
        ),
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.framework",
            deploymentTargets: .iOS("17.0.0"),
            infoPlist: .default,
            buildableFolders: [
                "Modules/Framework",
            ],
            dependencies: []
        ),
    ]
)
