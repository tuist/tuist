import ProjectDescription

let config = Config(
    plugins: [
        .local(path: .relativeToManifest("../../LocalPlugin")),
        .git(url: "https://github.com/Tuist/ExampleTuistPlugin", tag: "3.0.0"),
    ]
)
