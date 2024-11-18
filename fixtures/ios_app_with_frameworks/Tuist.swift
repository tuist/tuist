import ProjectDescription

let tuist = Tuist(
    fullHandle: "tuist/ios_app_with_frameworks",
    url: "https://canary.tuist.dev",
    generationOptions: .options(
        optionalAuthentication: true
    )
)
