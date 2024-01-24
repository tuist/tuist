import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        Target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "io.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"]
        ),
        Target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: .default,
            sources: ["Targets/App/Tests/**"],
            dependencies: [
                .target(name: "App"),
            ]
        ),
        Target(
            name: "tvOSFramework",
            destinations: [.appleTv],
            product: .framework,
            bundleId: "io.tuist.tvOSFramework",
            infoPlist: .default,
            sources: "Targets/tvOSFramework/Sources/**"
        ),
        Target(
            name: "tvOSFrameworkTests",
            destinations: [.appleTv],
            product: .unitTests,
            bundleId: "io.tuist.tvOSFrameworkTests",
            infoPlist: .default,
            sources: "Targets/tvOSFramework/Tests/**",
            dependencies: [
                .target(name: "tvOSFramework"),
            ]
        ),
        Target(
            name: "MacFramework",
            destinations: [.mac],
            product: .framework,
            bundleId: "io.tuist.MacFramework",
            deploymentTargets: .macOS("10.15"),
            infoPlist: .default,
            sources: "Targets/MacFramework/Sources/**",
            settings: .settings(
                base: [
                    "CODE_SIGN_IDENTITY": "",
                    "CODE_SIGNING_REQUIRED": "NO",
                ]
            )
        ),
        Target(
            name: "MacFrameworkTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "io.tuist.MacFrameworkTests",
            deploymentTargets: .macOS("10.15"),
            infoPlist: .default,
            sources: "Targets/MacFramework/Tests/**",
            dependencies: [
                .target(name: "MacFramework"),
            ],
            settings: .settings(
                base: [
                    "CODE_SIGN_IDENTITY": "",
                    "CODE_SIGNING_REQUIRED": "NO",
                ]
            )
        ),
    ]
)
