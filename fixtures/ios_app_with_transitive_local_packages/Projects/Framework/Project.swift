import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .package(path: "//Projects/Package")
    ],
    targets: [
        Target(name: "Framework",
               platform: .iOS,
               product: .framework,
               bundleId: "io.tuist.Framework",
               infoPlist: .default,
               sources: "Sources/**",
               dependencies: [
                   .package(product: "Library"),
        ]),
    ]
)
