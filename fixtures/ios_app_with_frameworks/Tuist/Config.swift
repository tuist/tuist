import ProjectDescription

let config = Config(
    cloud: .cloud(
        projectId: "tuist/tuist-cloud-acceptance-tests",
        url: "https://cloud-canary.tuist.io",
        options: [.optional]
    )
)
