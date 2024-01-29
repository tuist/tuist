import ProjectDescription

let project = Project(
    name: "MyStaticFramework",
    targets: [
        .target(
            name: "MyStaticFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.MyStaticFramework",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                /* Target dependencies can be defined here */
                // .framework(path: "Frameworks/MyStaticFramework.framework")
            ],
            settings: .settings(base: [
                "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
            ])
        ),
    ]
)
