import ProjectDescription

let settings = Settings(base: [
    "HEADER_SEARCH_PATHS": "path/to/lib/include",
])
let project = Project(name: "MainApp",
                      settings: settings,
                      targets: [
                          Target(name: "App",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.App",
                                 infoPlist: "Config/App-Info.plist",
                                 sources: "Sources/**",
                                 resources: [
                                     .glob(pattern: "Resources/**/*.txt")
                                 ],
                                 headers: Headers(public: "Sources/Headers/**/Public*.h",
                                                  private: "Sources/Headers/Private*.h",
                                                  project: "Sources/Headers/Project*.h"),
                                 dependencies: [
                                     .project(target: "Framework1", path: "../Framework1"),
                                     .project(target: "Framework2", path: "../Framework2"),
                                     .project(target: "Framework3", path: "../Framework3"),
                                     .project(target: "Framework4", path: "../Framework4"),
                                     .project(target: "Framework5", path: "../Framework5")]
                                 ),
                          Target(name: "AppTests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 bundleId: "io.tuist.AppTests",
                                 infoPlist: "Config/AppTests-Info.plist",
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "App"),
                          ])],
                          additionalFiles: [.glob(pattern: "AdditionalFiles/*")])
