import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "StickersPackExtension"),
                .target(name: "NotificationServiceExtension"),
                .target(name: "WidgetExtension"),
                .target(name: "AppIntentExtension"),
            ]
        ),
        // We need a separate app to test out Message Extensions
        // as having both stickers pack and message extensions in one app
        // doesn't seem to be supported.
        .target(
            name: "AppWithMessagesExtension",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App2",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "MessageExtension"),
                .target(name: "NotificationServiceExtension"),
            ]
        ),
        .target(
            name: "StickersPackExtension",
            destinations: .iOS,
            product: .stickerPackExtension,
            bundleId: "io.tuist.App.StickersPackExtension",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "$(PRODUCT_NAME)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.message-payload-provider",
                    "NSExtensionPrincipalClass": "StickerBrowserViewController",
                ],
            ]),
            sources: [],
            resources: ["StickersPackExtension/**"],
            dependencies: [
            ]
        ),
        .target(
            name: "NotificationServiceExtension",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "io.tuist.App.NotificationServiceExtension",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "$(PRODUCT_NAME)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.usernotifications.service",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).NotificationService",
                ],
            ]),
            sources: "NotificationServiceExtension/**",
            dependencies: [
            ]
        ),
        .target(
            name: "MessageExtension",
            destinations: .iOS,
            product: .messagesExtension,
            bundleId: "io.tuist.App2.MessageExtension",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "$(PRODUCT_NAME)",
                "NSExtension": [
                    "NSExtensionMainStoryboard": "MainInterface",
                    "NSExtensionPointIdentifier": "com.apple.message-payload-provider",
                ],
            ]),
            sources: "MessageExtension/Sources/**",
            resources: "MessageExtension/Resources/**",
            dependencies: [
            ]
        ),
        .target(
            name: "WidgetExtension",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "io.tuist.App.WidgetExtension",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "$(PRODUCT_NAME)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
                ],
            ]),
            sources: "WidgetExtension/Sources/**",
            resources: "WidgetExtension/Resources/**",
            dependencies: [
                .target(name: "StaticFramework"),
            ]
        ),
        .target(
            name: "StaticFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.App.StaticFramework",
            infoPlist: .default,
            sources: "StaticFramework/Sources/**"
        ),
        .target(
            name: "AppIntentExtension",
            destinations: .iOS,
            product: .extensionKitExtension,
            bundleId: "io.tuist.App.AppIntentExtension",
            infoPlist: .extendingDefault(with: [
                "EXAppExtensionAttributes": [
                    "EXExtensionPointIdentifier": "com.apple.appintents-extension",
                ],
            ]),
            sources: "AppIntentExtension/Sources/**"
        ),
    ]
)
