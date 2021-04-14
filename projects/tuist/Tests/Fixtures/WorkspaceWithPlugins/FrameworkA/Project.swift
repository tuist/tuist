import LocalPlugin
import ProjectDescription

let project = Project(
    name: "FrameworkA",
    targets: [
        .framework(
            name: "FrameworkA",
            dependencies: [
                .project(target: "FrameworkB", path: "//FrameworkB"),
            ]
        ),
    ]
)
