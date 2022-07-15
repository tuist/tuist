import ProjectDescription

let config = Config(
    plugins: [
        .local(path: .relativeToManifest("../../LocalPlugin")),
        .git(url: "https://github.com/woohyunjin06/ExampleTuistPlugin", tag: "3.1.0"),
    ]
)
