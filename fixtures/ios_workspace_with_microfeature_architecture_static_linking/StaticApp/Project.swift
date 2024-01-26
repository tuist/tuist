import ProjectDescription

let project = Project(
    name: "StaticApp",
    targets: [
        .target(
            name: "StaticApp",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.StaticApp",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                /* Target dependencies can be defined here */
                // .framework(path: "Frameworks/MyFramework.framework")
                .project(target: "FrameworkA", path: "../Frameworks/FeatureAFramework"),
            ]
        ),
        .target(
            name: "StaticAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.StaticAppTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "StaticApp"),
            ]
        ),
    ]
)
