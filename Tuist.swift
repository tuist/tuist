import ProjectDescription

let config = Config(
    fullHandle: "tuist/ios_app_with_frameworks",
    swiftVersion: .init("5.10"),
    generationOptions: .options(
        optionalAuthentication: true
    )
)
