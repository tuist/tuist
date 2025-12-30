import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: [
                .glob(
                    "App/Sources/**",
                    excluding: "App/Sources/**/*ExcludeMe.swift"
                ),
            ],
            dependencies: [],
            additionalFiles: [
                "**/.*.yml",
                "App/*.{entitlements,xcconfig}",
            ]
        ),
    ]
)
