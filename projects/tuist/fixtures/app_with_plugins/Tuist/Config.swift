import ProjectDescription

let config = Config(
    plugins: [
        .local(path: .relativeToManifest("../../LocalPlugin")),
        .git(url: "https://github.com/tuist/ExampleTuistPlugin", tag: "3.0.0"),
    ]
)
