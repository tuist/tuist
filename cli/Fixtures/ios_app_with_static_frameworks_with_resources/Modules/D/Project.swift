import ProjectDescription

let project = Project(
    name: "D",
    targets: [
        .target(
            name: "D",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.D",
            infoPlist: "Info.plist",
            sources: "Sources/**",
            dependencies: [
            ]
        ),
    ]
)
