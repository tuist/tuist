import ProjectDescription

/// These are necessary for the compiler to find the Workflow's SDK and link against it.
let workflowExtensionSettings: SettingsDictionary = [
    "ADDITIONAL_SDKS": "/Library/Developer/SDKs/WorkflowExtensionSDK.sdk $(inherited)",
    "OTHER_LDFLAGS": "-fapplication-extension -e _ProExtensionMain -lProExtension",
    "FRAMEWORK_SEARCH_PATHS": "/Library/Frameworks $(inherited)",
    "LIBRARY_SEARCH_PATHS": "/usr/lib $(inherited)",
    "SWIFT_OBJC_BRIDGING_HEADER": "$SRCROOT/Workflow/Workflow-Bridging-Header.h",
    "HEADER_SEARCH_PATHS": "/usr/include $(inherited)",
]

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.tuist.app",
            infoPlist: .default,
            sources: "App/**",
            copyFiles: [
                .productsDirectory(
                    name: "Embed Extension Points",
                    subpath: "App.app/Contents/Extensions",
                    files: [
                        "App/Resources/App.appextensionpoint",
                    ]
                ),
            ],
            dependencies: [
                .target(name: "Workflow"),
                .target(name: "ExtensionKitExtension"),
            ],
            additionalFiles: [
                "App/Resources/App.appextensionpoint",
            ]
        ),
        .target(
            name: "Workflow",
            destinations: [.mac],
            product: .appExtension,
            bundleId: "dev.tuist.app.workflow",
            infoPlist: .extendingDefault(with: [
                "NSExtensionPointIdentifier": "com.apple.FinalCut.WorkflowExtension",
                "ProExtensionPrincipalViewControllerClass": "$(PRODUCT_MODULE_NAME).WorkflowViewController",
            ]),
            sources: "Workflow/Sources/**",
            resources: "Workflow/Resources/**",
            settings: .settings(configurations: [
                .debug(name: "Debug", settings: workflowExtensionSettings, xcconfig: nil),
                .release(name: "Release", settings: workflowExtensionSettings, xcconfig: nil),
            ])
        ),
        .target(
            name: "ExtensionKitExtension",
            destinations: .macOS,
            product: .extensionKitExtension,
            bundleId: "dev.tuist.app.extensionKitExtension",
            infoPlist: .extendingDefault(with: [
                "EXAppExtensionAttributes": [
                    "EXExtensionPointIdentifier": "dev.tuist.app.extension-point",
                ],
            ]),
            sources: "ExtensionKitExtension/Sources/**",
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": .boolean(true),
            ])
        ),
    ]
)
