import ProjectDescription

let project = Project(
    name: "Prebuilt",
    targets: [
        Target(name: "PrebuiltStaticFramework",
               platform: .iOS,
               product: .staticFramework,
               bundleId: "io.tuist.PrebuiltStaticFramework",
               infoPlist: "Config/Info.plist",
               sources: "Sources/**",
               dependencies: [])
    ]
)
