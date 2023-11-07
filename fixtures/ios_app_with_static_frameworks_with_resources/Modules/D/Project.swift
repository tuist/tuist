import ProjectDescription

let project = Project(
    name: "D",
    targets: [
        Target(
            name: "D",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.D",
            infoPlist: "Info.plist",
            sources: "Sources/**",
            dependencies: [
            ]
        ),
    ]
)
