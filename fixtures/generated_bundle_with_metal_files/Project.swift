import ProjectDescription

let project = Project(
    name: "Bundle",
    targets: [
        .target(
            name: "Bundle",
            destinations: .iOS,
            product: .bundle,
            bundleId: "io.tuist.Bundle",
            sources: ["Bundle/Sources/**"],
            dependencies: []
        ),
    ]
)
