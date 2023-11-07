import ProjectDescription

let project = Project(
    name: "FrameworkA",
    targets: [
        Target(
            name: "FrameworkA",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.FrameworkA",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                /* Target dependencies can be defined here */
                // .framework(path: "Frameworks/MyFramework.framework")
                .project(target: "FrameworkB", path: "../FrameworkB"),
            ]
        ),
        Target(
            name: "FrameworkATests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.FrameworkATests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "FrameworkA"),
            ]
        ),
    ]
)
