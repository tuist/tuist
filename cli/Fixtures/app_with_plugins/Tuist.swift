import ProjectDescription

let tuist = Tuist(
    plugins: [
        .local(path: .relativeToManifest("../LocalPlugin")),
        .git(url: "https://github.com/tuist/ExampleTuistPlugin", tag: "3.2.1"),
    ]
)
