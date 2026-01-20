import ProjectDescription

let tuist = Tuist(
    fullHandle: "tuist/generated_project_with_caching_enabled",
    url: "https://canary.tuist.dev",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
