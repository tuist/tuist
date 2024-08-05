import ProjectDescription

let config = Config(
    fullHandle: "tuist/tuist",
    url: "https://cloud.tuist.io",
    swiftVersion: .init("5.10"),
    generationOptions: .options(
        optionalAuthentication: true
    )
)
