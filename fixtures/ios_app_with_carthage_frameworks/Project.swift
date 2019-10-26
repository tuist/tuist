import ProjectDescription

let project = Project(name: "App",
                      targets: [
                          Target(name: "App",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.App",
                                 infoPlist: .extendingDefault(with: [:]),
                                 sources: "Sources/**",
                                 resources: "Sources/Main.storyboard",
                                 dependencies: [
                                    .framework(path: "Carthage/Build/iOS/RxSwift.framework")
                          ])
])
