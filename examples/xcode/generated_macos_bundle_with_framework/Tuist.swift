import ProjectDescription

let config = Config(
    fullHandle: "tuist/xcode_app",
    url: "https://canary.tuist.dev",
    project: .tuist(generationOptions: .options(
        optionalAuthentication: true
    ))
)
