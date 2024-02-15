import ProjectDescription

let project = Project(
    name: "MyFramework",
    targets: [
        .target(
            name: "MyFramework",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.MyFramework",
            infoPlist: "Info.plist",
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
        .target(
            name: "MyFrameworkTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.MyFrameworkTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "MyFramework"),
            ]
        ),
    ]
)
