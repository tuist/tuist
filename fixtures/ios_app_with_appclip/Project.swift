import ProjectDescription

let project = Project(name: "App",
                      organizationName: "Tuist",
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.App",
                               infoPlist: .default,
                               sources: ["App/Sources/**",],
                               dependencies: [
                                .target(name: "AppClip"),
                                ]),
                        Target(name: "AppClip",
                               platform: .iOS,
                               product: .appClip,
                               bundleId: "io.tuist.App.Clip",
                               infoPlist: .default,
                               sources: ["AppClip/Sources/**",],
                               entitlements: "AppClip/Entitlements/AppClip.entitlements",
                               dependencies: [
                                .sdk(name: "AppClip.framework", status: .required),
                                ]),
                        Target(name: "AppClipTests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.AppClipTests",
                               infoPlist: .default,
                               sources: ["AppClipTests/Tests/**"],
                               dependencies: [
                                .target(name: "AppClip")
                               ]),
                        Target(name: "AppClipUITests",
                               platform: .iOS,
                               product: .uiTests,
                               bundleId: "io.tuist.AppClipUITests",
                               infoPlist: .default,
                               sources: ["AppClipUITests/Tests/**"],
                               dependencies: [
                                .target(name: "AppClip")
                               ])
                      ])
