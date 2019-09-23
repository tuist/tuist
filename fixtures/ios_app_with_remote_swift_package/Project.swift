import ProjectDescription

let project = Project(name: "App",
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.App",
                               infoPlist: "Support/Info.plist",
                               sources: ["Sources/**"],
                               resources: [
                                       /* Path to resouces can be defined here */
                                       // "Resources/**"
                               ],
                               dependencies: [
                                    .package(url: "https://github.com/ReactiveX/RxSwift", productName: "RxSwift", .upToNextMajor(from: "5.0")),
                                ]),
                        Target(name: "AppTests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.AppTests",
                               infoPlist: "Support/Tests.plist",
                               sources: "Tests/**",
                               dependencies: [
                                    .target(name: "App")
                               ])
                      ])
