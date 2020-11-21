import ProjectDescription

public let macTargets: [Target] = [
    Target(
        name: "MacFramework",
        platform: .macOS,
        product: .framework,
        bundleId: "io.tuist.MacFramework",
        deploymentTarget: .macOS(targetVersion: "10.15.0"),
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
        deploymentTarget: .macOS(targetVersion: "10.15.0"),
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
