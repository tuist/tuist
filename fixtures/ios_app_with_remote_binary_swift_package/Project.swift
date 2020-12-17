import ProjectDescription


let project = Project(name: "App",
                      packages: [
                        .package(url: "https://github.com/firebase/firebase-ios-sdk", .upToNextMajor(from: "7.1.0")),
                      ],
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.App",
                               infoPlist: "Support/Info.plist",
                               sources: ["Sources/**"],
                               resources: [],
                               dependencies: [
                                    // Firebase analytics is a binary target
                                    .package(product: "FirebaseAnalytics"),
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
