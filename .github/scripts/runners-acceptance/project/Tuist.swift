import ProjectDescription

let tuist = Tuist(
    fullHandle: "tuist/tuist",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
