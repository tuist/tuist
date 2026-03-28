import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app",
            infoPlist: .default,
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"]
        ),
    ],
    resourceSynthesizers: [
        .files(
            extensions: ["json"],
            context: ["accessModifier": "internal"]
        ),
    ]
)
