import ProjectDescription

let tuist = Tuist(
    fullHandle: "tuist/multiplatform_app_with_extension",
    url: "https://canary.tuist.dev",
    project: .tuist(
        generationOptions: .options(
            optionalAuthentication: true,
            buildInsightsDisabled: false
        )
    )
)
