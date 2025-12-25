import ProjectDescription

let project = Project(
    name: "FrameworkA",
    targets: [
        .target(
            name: "FrameworkA",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.FrameworkA",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: [
                // Path to resources can be defined here
                // "Resources/**"
            ],
            dependencies: [
                // Target dependencies can be defined here
                // .framework(path: "Frameworks/MyFramework.framework")
                .project(target: "FrameworkB", path: "../FrameworkB"),
            ]
        ),
        .target(
            name: "FrameworkATests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.FrameworkATests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "FrameworkA"),
            ]
        ),
    ]
)
