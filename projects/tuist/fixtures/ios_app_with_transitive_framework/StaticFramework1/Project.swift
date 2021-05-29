import ProjectDescription

let project = Project(
    name: "StaticFramework1",
    targets: [
        Target(name: "StaticFramework1",
               platform: .iOS,
               product: .staticFramework,
               bundleId: "io.tuist.StaticFramework1",
               infoPlist: .default,
               sources: "Sources/**",
               dependencies: [
                   .framework(path: "../Framework2/prebuilt/iOS/Framework2.framework"),
        ]),
        Target(name: "StaticFramework1Tests",
               platform: .iOS,
               product: .unitTests,
               bundleId: "io.tuist.StaticFramework1Tests",
               infoPlist: .default,
               sources: "Tests/**",
               dependencies: [
                .target(name: "StaticFramework1"),
            ]),
    ]
)
