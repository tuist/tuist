import ProjectDescription

let project = Project(
    name: "generated_project_with_caching_enabled",
    targets: [
        .target(
            name: "generated_project_with_caching_enabled",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.generated-project-with-caching-enabled",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            buildableFolders: [
                "generated_project_with_caching_enabled/Sources",
                "generated_project_with_caching_enabled/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "generated_project_with_caching_enabledTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.generated-project-with-caching-enabledTests",
            infoPlist: .default,
            buildableFolders: [
                "generated_project_with_caching_enabled/Tests",
            ],
            dependencies: [.target(name: "generated_project_with_caching_enabled")]
        ),
    ]
)
