import ProjectDescription

let config = Config(
    cloud: .cloud(
        projectId: "tuist/tuist",
        url: "https://cloud.tuist.io",
        options: [.optional, .analytics]
    ),
    swiftVersion: .init("5.6.0")
)
