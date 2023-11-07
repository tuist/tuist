import ProjectDescription

let project = Project(
    name: "MyFramework",
    targets: [
        Target(
            name: "MyFramework",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.MyFramework",
            infoPlist: .default,
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                /* Target dependencies can be defined here */
                // .framework(path: "Frameworks/MyFramework.framework")
            ],
            settings: .settings(base: [
                "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
            ])
        ),
    ]
)
