import ProjectDescription

let config = Config(
    fullHandle: "tuist/ios_app_with_frameworks",
    url: "https://canary.tuist.dev",
    generationOptions: .options(
        optionalAuthentication: true,
        buildInsightsDisabled: false
    )
)
