import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            sources: ["Sources/**"],
            dependencies: [
                .external(name: "GoogleSignIn")
            ]
        )
    ]
)
