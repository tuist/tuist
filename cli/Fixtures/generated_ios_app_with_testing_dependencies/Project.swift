import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.App",
            deploymentTargets: .macOS("15.7"),
            infoPlist: .default,
            buildableFolders: [
                "App/Sources",
                "App/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "AppTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            deploymentTargets: .macOS("15.7"),
            infoPlist: .default,
            buildableFolders: [
                "App/Tests",
            ],
            dependencies: [
                .target(name: "App"),
                .external(name: "Quick"),
                .external(name: "Nimble"),
            ]
        ),
    ]
)
