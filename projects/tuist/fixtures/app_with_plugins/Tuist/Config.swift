import ProjectDescription

let config = Config(
    plugins: [
        .local(path: .relativeToManifest("../../LocalPlugin")),
        // TODO: Change back to tuist organization
        .git(url: "https://github.com/woohyunjin06/ExampleTuistPlugin", tag: "3.1.0"),
    ]
)
