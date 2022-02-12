import ProjectDescription

let config = Config(
    plugins: [
        .local(path: .relativeToManifest("../../LocalPlugin")),
        // TODO: Change back to tuist organization
        .git(url: "https://github.com/fortmarek/ExampleTuistPlugin", tag: "0.4.0"),
    ]
)
