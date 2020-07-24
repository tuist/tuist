import ProjectDescription

let project = Project(name: "App",
                      packages: [
                      ],
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.App",
                               infoPlist: .default,
                               sources: ["Sources/**"],
                               dependencies: [
                                .project(target: "Framework", path: "//Projects/Framework"),
                        ]),
                        Target(name: "AppTests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.AppTests",
                               infoPlist: .default,
                               sources: "Tests/**",
                               dependencies: [
                                .target(name: "App")
                        ])
])
