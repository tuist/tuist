import ProjectDescription

let project = Project(
    name: "Framework2",
    targets: [
        Target(name: "Framework2",
               platform: .iOS,
               product: .framework,
               bundleId: "io.tuist.Framework2",
               infoPlist: "Config/Framework2-Info.plist",
               sources: "Sources/**",
               dependencies: [
                   
        ]),
    ]
)
