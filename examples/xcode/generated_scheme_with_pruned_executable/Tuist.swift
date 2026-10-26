import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            warningsAsErrors: .only([.schemeTargetNotFound])
        )
    )
)
