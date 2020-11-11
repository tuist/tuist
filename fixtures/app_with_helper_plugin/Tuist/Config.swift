import ProjectDescription

let config = Config(
    plugins: [
        .local(path: .relativeToRoot("LocalHelperPlugin"))
    ],
    generationOptions: []
)
