import ProjectDescription

let project = Project(
    name: "Framework1",
    targets: [
        Target(name: "Framework1",
               platform: .iOS,
               product: .framework,
               bundleId: "io.tuist.Framework1",
               infoPlist: "Config/Framework1-Info.plist",
               sources: "Sources/**"
        )
    ]
)
