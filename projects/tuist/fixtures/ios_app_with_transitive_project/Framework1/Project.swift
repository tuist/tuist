import ProjectDescription

let project = Project(
    name: "Framework1",
    targets: [
        Target(
            name: "Framework1-iOS",
            platform: .iOS,
            product: .staticFramework,
            productName: "Framework1",
            bundleId: "io.tuist.Framework1",
            infoPlist: "Config/Framework1-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "Framework2-iOS", path: "../Framework2"),
            ]
        ),
        Target(
            name: "Framework1-macOS",
            platform: .macOS,
            product: .framework,
            productName: "Framework1",
            bundleId: "io.tuist.Framework1",
            infoPlist: "Config/Framework1-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "Framework2-macOS", path: "../Framework2"),
            ]
        ),
        Target(
            name: "Framework1Tests-iOS",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.Framework1Tests",
            infoPlist: "Tests/Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework1-iOS"),
            ]
        ),
        Target(
            name: "Framework1Tests-macOS",
            platform: .macOS,
            product: .unitTests,
            bundleId: "io.tuist.Framework1Tests",
            infoPlist: "Tests/Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework1-macOS"),
            ]
        ),
    ]
)
