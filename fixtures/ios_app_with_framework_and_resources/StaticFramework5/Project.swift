import ProjectDescription

let project = Project(
    name: "StaticFramework5",
    targets: [
        .target(
            name: "StaticFramework5",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework5",
            infoPlist: .default,
            resources: "Resources/**",
            dependencies: [
            ],
            settings: .settings(base: ["SWIFT_STRICT_CONCURRENCY": .string("complete")], defaultSettings: .recommended())
        ),
    ]
)
