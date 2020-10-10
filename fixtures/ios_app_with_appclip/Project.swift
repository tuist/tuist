import ProjectDescription

let project = Project(name: "App",
                      organizationName: "Tuist",
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.App",
                               infoPlist: "App/Configs/Info.plist",
                               sources: ["App/Sources/**",],
                               resources: ["App/Resources/**"],
                               dependencies: [
                                .target(name: "AppClip"),
                                ]),
                        Target(name: "AppClip",
                               platform: .iOS,
                               product: .appClip,
                               bundleId: "io.tuist.App.Clip",
                               infoPlist: "AppClip/Configs/Info.plist",
                               sources: ["AppClip/Sources/**",],
                               resources: ["AppClip/Resources/**"],
                               entitlements: "AppClip/Entitlements/AppClip.entitlements",
                               dependencies: [
                                .sdk(name: "AppClip.framework", status: .required),
                                ]),
                      ])
