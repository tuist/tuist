import ProjectDescription

let config = Config(
    cloud: .cloud(
        projectId: "tuist/tuist-cloud-acceptance-tests",
        url: "http://127.0.0.1:8080",
        options: [.optional]
    )
)
