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
                                    .project(target: "FrameworkA", path: "Frameworks/FrameworkA"),
                                    .package(path: "Packages/PackageA", productName: "LibraryA"),
                                    .package(path: "Packages/PackageA", productName: "LibraryB"),
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