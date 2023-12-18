import ProjectDescription

let project = Project(
    name: "MergeableXCFramework",
    targets: [
        Target(
            name: "MergeableXCFramework",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.MergeableXCFramework",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [],
            settings: .settings(base: [
                "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
                "MERGEABLE_LIBRARY": "YES",
            ]),
            mergeable: true
        ),
        Target(
            name: "MergeableXCFrameworkTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.MergeableXCFrameworkTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "MergeableXCFramework"),
            ]
        ),
    ]
)
