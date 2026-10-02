import ProjectDescription

let project = Project(
    name: "Palette",
    targets: [
        .target(
            name: "Palette",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.Palette",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/**"],
            headers: .headers(public: ["Sources/*.h"]),
            dependencies: [
                .project(target: "Renderer", path: "../Renderer"),
                .project(target: "Tokens", path: "../Tokens"),
            ]
        ),
    ]
)
