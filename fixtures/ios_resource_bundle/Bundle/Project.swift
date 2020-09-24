import ProjectDescription

let project = Project(
    name: "Resources Only",
    targets: [
        Target(name: "StaticFrameworkResources",
               platform: .iOS,
               product: .bundle,
               bundleId: "io.tuist.StaticFrameworkResources",
               infoPlist: .default,
               sources: [],
               resources: "Resources/**",
               dependencies: []),
    ]
)
