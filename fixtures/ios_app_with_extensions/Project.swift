import ProjectDescription

let project = Project(name: "App",
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.App",
                               infoPlist: "Info.plist",
                               sources: ["Sources/**"],
                               dependencies: [
                                    .target(name: "StickersPackExtension"),
                                    .target(name: "NotificationServiceExtension"),
                                ]),
                        // We need a seperate app to test out Message Extensions
                        // as having both stickers pack and message extensions in one app
                        // doesn't seem to be supported.
                        Target(name: "AppWithMessagesExtension",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.App",
                               infoPlist: "Info.plist",
                               sources: ["Sources/**"],
                               dependencies: [
                                    .target(name: "MessageExtension"),
                                    .target(name: "NotificationServiceExtension"),
                                ]),
                        Target(name: "StickersPackExtension",
                               platform: .iOS,
                               product: .stickerPackExtension,
                               bundleId: "io.tuist.App.StickersPackExtension",
                               infoPlist: .extendingDefault(with: [
                                       "CFBundleDisplayName": "$(PRODUCT_NAME)",
                                       "NSExtension": [
                                               "NSExtensionPointIdentifier": "com.apple.message-payload-provider", 
                                               "NSExtensionPrincipalClass": "StickerBrowserViewController"
                                        ]
                                ]),
                               sources: [],
                               resources: ["StickersPackExtension/**"],
                               dependencies: [
                                    
                               ]),
                      Target(name: "NotificationServiceExtension",
                               platform: .iOS,
                               product: .appExtension,
                               bundleId: "io.tuist.App.NotificationServiceExtension",
                               infoPlist: .extendingDefault(with: [
                                       "CFBundleDisplayName": "$(PRODUCT_NAME)",
                                       "NSExtension": [
                                               "NSExtensionPointIdentifier": "com.apple.usernotifications.service", 
                                               "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).NotificationService"
                                        ]
                                ]),
                               sources: "NotificationServiceExtension/**",
                               dependencies: [
                                    
                               ]),
                         Target(name: "MessageExtension",
                               platform: .iOS,
                               product: .messagesExtension,
                               bundleId: "io.tuist.App.MessageExtension",
                               infoPlist: .extendingDefault(with: [
                                       "CFBundleDisplayName": "$(PRODUCT_NAME)",
                                       "NSExtension": [
                                               "NSExtensionMainStoryboard": "MainInterface",
                                               "NSExtensionPointIdentifier": "com.apple.message-payload-provider",
                                        ]
                                ]),
                               sources: "MessageExtension/Sources/**",
                               resources: "MessageExtension/Resources/**",
                               dependencies: [
                                    
                               ])
                ])