import ProjectDescription

let config = Config(
    cloud: .cloud(
        projectId: "tuist/tuist",
        url: "https://cloud.tuist.io",
        options: [.optional]
    ),
    swiftVersion: .init("5.8"),
    generationOptions: .options()
)
