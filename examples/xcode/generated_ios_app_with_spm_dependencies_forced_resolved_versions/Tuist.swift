import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--force-resolved-versions"])
    )
)
