import ProjectDescription

let debugAction = ExecutionAction(scriptText: "echo Debug", target: "App")
let debugScheme = Scheme(name: "App-Debug",
                         shared: true,
                         buildAction: BuildAction(targets: ["App"], preActions: [debugAction]),
                         testAction: TestAction(targets: ["AppTests"]),
                         runAction: RunAction(executable: "App", options: .options(simulatedLocation: .johannesburg)))

let releaseAction = ExecutionAction(scriptText: "echo Release", target: "App")
let releaseScheme = Scheme(name: "App-Release",
                           shared: true,
                           buildAction: BuildAction(targets: ["App"], preActions: [releaseAction]),
                           testAction: TestAction(targets: ["AppTests"]),
                           runAction: RunAction(executable: "App", options: .options(simulatedLocation: .custom(gpxFile: "Resources/Grand Canyon.gpx"))))

let userScheme = Scheme(name: "App-Local",
                        shared: false,
                        buildAction: BuildAction(targets: ["App"], preActions: [debugAction]),
                        testAction: TestAction(targets: ["AppTests"]),
                        runAction: RunAction(executable: "App"))

let project = Project(name: "MainApp",
                      targets: [
                          Target(name: "App",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.App",
                                 infoPlist: "Config/App-Info.plist",
                                 sources: "Sources/**",
                                 dependencies: [
                                     .project(target: "Framework1", path: "../Frameworks/Framework1"),
                                     .project(target: "Framework2", path: "../Frameworks/Framework2"),
                          ]),
                          Target(name: "AppTests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 bundleId: "io.tuist.AppTests",
                                 infoPlist: "Config/AppTests-Info.plist",
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "App"),
                          ])],
                      schemes: [debugScheme, releaseScheme, userScheme])


