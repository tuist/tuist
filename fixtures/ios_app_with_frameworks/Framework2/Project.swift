import ProjectDescription

let project = Project(name: "Framework2",
                      targets: [
                          Target(name: "Framework2",
                                 platform: [ .iOS, .macOS ],
                                 product: .framework,
                                 bundleId: "io.tuist.Framework2",
                                 infoPlist: "Config/Framework2-Info.plist",
                                 sources: "Sources/**",
                                 headers: Headers(public: "Sources/Public/**", 
                                                  private: "Sources/Private/**", 
                                                  project: "Sources/Project/**"),
                                 dependencies: []),

                          Target(name: "Framework2Tests",
                                 platform: [ .iOS, .macOS ],
                                 product: .unitTests,
                                 bundleId: "io.tuist.Framework2Tests",
                                 infoPlist: "Config/Framework2Tests-Info.plist",
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "Framework2"),
                          ]),
])
