import ProjectDescription

let workspace = Workspace(
    name: "Workspace",
    contents: [
        .group(name: "Application", contents: [
            .project(path: "App"),
        ]),
        .group(name: "Frameworks", contents: [
            .project(path: "Framework1"),
            .project(path: "Framework2"),
        ]),
    ]
)
