import ProjectDescription

let project = Project(
    name: "DynamicFrameworkA",
    targets: [
        Target(
            name: "DynamicFrameworkA",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.DynamicFrameworkA",
            infoPlist: .default,
            sources: ["Sources/**"],
            dependencies: [],
            mergeable: true
        ),
    ]
)
