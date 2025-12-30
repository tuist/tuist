import ProjectDescription

let project = Project(
    name: "StaticApp",
    targets: [
        .target(
            name: "StaticApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.StaticApp",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: [
                // Path to resources can be defined here
                // "Resources/**"
            ],
            dependencies: [
                // Target dependencies can be defined here
                // .framework(path: "Frameworks/MyFramework.framework")
                .project(target: "FrameworkA", path: "../Frameworks/FeatureAFramework"),
            ]
        ),
        .target(
            name: "StaticAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.StaticAppTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "StaticApp"),
            ]
        ),
    ]
)
