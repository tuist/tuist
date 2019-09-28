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
                                    .framework(path: "Prebuilt/prebuilt/PrebuiltStaticFramework.framework"),
                                    .package(path: "Packages/PackageA", productName: "LibraryA")
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
