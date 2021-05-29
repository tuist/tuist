import ProjectDescription

let project = Project(
    name: "Prebuilt",
    packages: [
        .package(path: "../Packages/PackageA")
    ],
    targets: [
        Target(name: "PrebuiltStaticFramework",
               platform: .iOS,
               product: .staticFramework,
               bundleId: "io.tuist.PrebuiltStaticFramework",
               infoPlist: "Config/Info.plist",
               sources: "Sources/**",
               dependencies: [
                   .package(product: "LibraryA")
                ])
    ]
)
