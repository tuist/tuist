import ProjectDescription

let project = Project(
    name: "Data",
    targets: [
        Target(
            name: "Data",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.Data",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                /* Target dependencies can be defined here */
                // .framework(path: "Frameworks/MyFramework.framework")
                .project(target: "Core", path: "../CoreFramework"),
            ]
        ),
        Target(
            name: "DataTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.DataFrameworkTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Data"),
            ]
        ),
    ]
)
