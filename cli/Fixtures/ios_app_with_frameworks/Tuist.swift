import ProjectDescription

let tuist = Tuist(
    fullHandle: "tuist/ios_app_with_frameworks",
    url: "http://localhost:8080",
    project: .tuist(
        generationOptions: .options(
            optionalAuthentication: true,
            buildInsightsDisabled: false
        )
    )
)
