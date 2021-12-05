import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.app(
    name: "App",
    dependencies: [
        .project(
            target: "FrameworkA",
            path: .relativeToRoot("FrameworkA")
        ),
    ]
)
