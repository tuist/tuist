import ProjectDescription

let config = Config(
    fullHandle: "tuist/tuist",
    swiftVersion: .init("5.10"),
    generationOptions: .options(
        optionalAuthentication: true,
        disableSandbox: true,
    )
)
