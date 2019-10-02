import ProjectDescription

let project = Project(
    name: "FrameworkA",
    targets: [
        Target(name: "FrameworkA",
               platform: .iOS,
               product: .staticFramework,
               bundleId: "io.tuist.FrameworkA",
               infoPlist: "Config/FrameworkA-Info.plist",
               sources: "Sources/**",
               dependencies: [
                   .package(path: "../../Packages/PackageA", productName: "LibraryA"),
        ]),
    ]
)
