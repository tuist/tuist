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
                                .target(name: "AppClips"),
                                ]),
                        Target(name: "AppClips",
                               platform: .iOS,
                               product: .appClips,
                               bundleId: "io.tuist.App.Clip",
                               infoPlist: "AppClips/Configs/Info.plist",
                               sources: ["AppClips/Sources/**",],
                               resources: ["AppClips/Resources/**"],
                               entitlements: "AppClips/Entitlements/AppClip.entitlements",
                               dependencies: [
                                .sdk(name: "AppClip.framework", status: .required),
                                ]),
                      ])
