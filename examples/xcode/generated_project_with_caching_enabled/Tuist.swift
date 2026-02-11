import ProjectDescription

let tuist = Tuist(
    fullHandle: "tuist/tuist",
    cache: .cache(
        upload: false
    ),
    url: "https://canary.tuist.dev",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    ),
)
