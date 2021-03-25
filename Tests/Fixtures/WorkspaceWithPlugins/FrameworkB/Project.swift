import LocalPlugin
import ProjectDescription

let project = Project(
    name: "FrameworkB",
    targets: [
        .framework(
            name: "FrameworkB"
        ),
    ]
)
