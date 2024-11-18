import ProjectDescription

let tuist = Tuist(
    fullHandle: "tuist/tuist",
    url: "https://cloud.tuist.io",
    swiftVersion: .init("5.10"),
    generationOptions: .options(
        optionalAuthentication: true
    )
)
