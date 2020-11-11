import ProjectDescription

let config = Config(
    plugins: [
        .git(url: "https://github.com/tuist/ExampleTuistHelpersPlugin.git", branch: "main")
    ],
    generationOptions: []
)
