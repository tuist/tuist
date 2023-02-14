import ProjectDescription

let config = Config(
    cloud: .cloud(projectId: "tuist/tuist", url: "https://cloud.tuist.io", options: [.optional]),
    cache: .cache(path: .relativeToRoot(".cache")),
    swiftVersion: .init("5.6.0")
)
