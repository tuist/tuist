import ProjectDescription

let userScheme = Scheme(name: "App-Local",
                        shared: false,
                        buildAction: BuildAction(targets: ["App"], preActions: []),
                        testAction: TestAction(targets: [.init(target: TargetReference(projectPath: "//Framework", target: "Framework"))]),
                        runAction: RunAction(executable: "App"))

let project = Project(name: "MainApp",
                      targets: [
                          Target(name: "App",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.App",
                                 infoPlist: .default,
                                 sources: "Sources/**",
                                 dependencies: [
                                     .project(target: "Framework", path: "//Framework"),
                          ]),
                          Target(name: "AppTests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 bundleId: "io.tuist.AppTests",
                                 infoPlist: .default,
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "App"),
                          ])],
                      schemes: [userScheme])


