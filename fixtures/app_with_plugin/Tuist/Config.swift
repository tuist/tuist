import ProjectDescription

let config = Config(
    plugins: [
        .local(path: .relativeToManifest("../../LocalPlugin")),
        .git(url: "https://github.com/tuist/ExampleTuistPlugin.git", tag: "1.0.0")
    ],
    generationOptions: []
)
