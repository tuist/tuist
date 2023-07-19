import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: .default,
            sources: "App/**",
            dependencies: [
                .external(name: "GoogleSignIn"),
                .external(name: "GoogleSignInSwift"),
            ]
        )
    ]
)
