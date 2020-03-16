import ProjectDescription

let project = Project(name: "App",
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.App",
                               infoPlist: .default,
                               sources: "Sources/**",
                               resources: "Sources/Main.storyboard",
                               dependencies: [
                                .target(name: "Core"),
                                .framework(path: "Carthage/Build/iOS/RxSwift.framework")
                        ]),
                        Target(name: "AppTests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.AppTests",
                               infoPlist: .default,
                               sources: "Tests/**",
                               dependencies: [
                                .target(name: "App"),
                        ]),
                        Target(name: "Core",
                               platform: .iOS,
                               product: .framework,
                               bundleId: "io.tuist.Core",
                               infoPlist: .default,
                               sources: "Core/**",
                               dependencies: [
                                .framework(path: "Carthage/Build/iOS/RxSwift.framework"),
                        ]),
                        Target(name: "CoreTests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.CoreTests",
                               infoPlist: .default,
                               sources: "CoreTests/**",
                               dependencies: [
                                .target(name: "Core")
                        ])
    ], schemes: [
        Scheme(name: "AllTargets",
               shared: true,
               buildAction: BuildAction(targets: [
                "App",
                "AppTests",
                "Core",
                "CoreTests"
               ]))
])
