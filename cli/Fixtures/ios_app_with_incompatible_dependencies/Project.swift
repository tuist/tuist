import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.mac],
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Info.plist",
            sources: "App/**",
            dependencies: [
                .target(name: "Framework"),
            ],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "",
                "CODE_SIGNING_REQUIRED": "NO",
            ])
        ),
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.Framework",
            infoPlist: "Framework.plist",
            sources: "Framework/**",
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "",
                "CODE_SIGNING_REQUIRED": "NO",
            ])
        ),
    ]
)
