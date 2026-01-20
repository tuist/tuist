import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app",
            sources: "App/**"
        ),
    ],
    schemes: [
        .scheme(
            name: "CustomMetalConfig",
            buildAction: .buildAction(targets: [.target("App")]),
            runAction: .runAction(
                metalOptions: .options(
                    apiValidation: false,
                    shaderValidation: true,
                    showGraphicsOverview: true,
                    logGraphicsOverview: true
                )
            )
        ),
        .scheme(
            name: "DefaultMetalConfig",
            buildAction: .buildAction(targets: [.target("App")])
        ),
    ]
)
