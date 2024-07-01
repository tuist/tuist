import ProjectDescription

let config = Config(
    cloud: .cloud(
        projectId: "tuist/tuist-cloud-acceptance-tests",
        url: "http://localhost:8080",
        options: [.optional]
    )
)
