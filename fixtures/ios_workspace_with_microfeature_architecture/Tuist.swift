import ProjectDescription

let tuist = Tuist(
    plugins: [
        .local(path: .relativeToRoot("Plugin")),
    ]
)
