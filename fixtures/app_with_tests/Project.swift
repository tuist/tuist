import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            deploymentTarget: .iOS(targetVersion: "13.0", devices: .iphone),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"]
        ),
        Target(
            name: "AppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: .default,
            sources: ["Targets/App/Tests/**"],
            dependencies: [
                .target(name: "App")
            ]
        ),
        Target(
            name: "tvOSFramework",
            platform: .tvOS,
            product: .framework,
            bundleId: "io.tuist.tvOSFramework",
            infoPlist: .default,
            sources: "Targets/tvOSFramework/Sources/**"
        ),
        Target(
            name: "tvOSFrameworkTests",
            platform: .tvOS,
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
            platform: .macOS,
            product: .framework,
            bundleId: "io.tuist.MacFramework",
            infoPlist: .default,
            sources: "Targets/MacFramework/Sources/**",
            settings: Settings(
                base: [
                    "CODE_SIGN_IDENTITY": "",
                    "CODE_SIGNING_REQUIRED": "NO"
                ]
            )
        ),
        Target(
            name: "MacFrameworkTests",
            platform: .macOS,
            product: .unitTests,
            bundleId: "io.tuist.MacFrameworkTests",
            infoPlist: .default,
            sources: "Targets/MacFramework/Tests/**",
            dependencies: [
                .target(name: "MacFramework"),
            ],
            settings: Settings(
                base: [
                    "CODE_SIGN_IDENTITY": "",
                    "CODE_SIGNING_REQUIRED": "NO"
                ]
            )
        ),
    ]
)
