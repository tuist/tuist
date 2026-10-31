import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        installOptions: .options(
            passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"]
        )
    )
)
