import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: .default,
            sources: ["Targets/App/Tests/**"],
            dependencies: [
                .target(name: "App"),
            ]
        ),
        .target(
            name: "tvOSFramework",
            destinations: [.appleTv],
            product: .framework,
            bundleId: "dev.tuist.tvOSFramework",
            infoPlist: .default,
            sources: "Targets/tvOSFramework/Sources/**"
        ),
        .target(
            name: "tvOSFrameworkTests",
            destinations: [.appleTv],
            product: .unitTests,
            bundleId: "dev.tuist.tvOSFrameworkTests",
            infoPlist: .default,
            sources: "Targets/tvOSFramework/Tests/**",
            dependencies: [
                .target(name: "tvOSFramework"),
            ]
        ),
        .target(
            name: "MacFramework",
            destinations: [.mac],
            product: .framework,
            bundleId: "dev.tuist.MacFramework",
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
        .target(
            name: "MacFrameworkTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "dev.tuist.MacFrameworkTests",
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
