import ProjectDescription

let project = Project(
    name: "DynamicFrameworkB",
    targets: [
        Target(
            name: "DynamicFrameworkB",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.DynamicFrameworkB",
            infoPlist: .default,
            sources: ["Sources/**"],
            dependencies: [],
            mergeable: true
        ),
    ]
)
