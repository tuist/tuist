import ProjectDescription

let project = Project(
    name: "FrameworkB",
    targets: [
        .target(
            name: "FrameworkB",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.FrameworkB",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: [
                // Path to resources can be defined here
                // "Resources/**"
            ],
            dependencies: [
                // Target dependencies can be defined here
                // .framework(path: "Frameworks/MyFramework.framework")
                .project(target: "FrameworkA", path: "../FrameworkA"),
            ]
        ),
        .target(
            name: "FrameworkBTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.FrameworkBTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "FrameworkB"),
            ]
        ),
    ]
)
