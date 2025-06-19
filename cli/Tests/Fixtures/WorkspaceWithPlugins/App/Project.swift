import LocalPlugin
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .app(
            name: "App",
            dependencies: [
                .project(target: "FrameworkA", path: "//FrameworkA"),
            ]
        ),
    ]
)
