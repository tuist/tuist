import ProjectDescription

/**
 These are necessary for the compiler to find the Workflow's SDK and link against it.
 **/
let workflowExtensionSettings: SettingsDictionary = [
    "ADDITIONAL_SDKS": "/Library/Developer/SDKs/WorkflowExtensionSDK.sdk $(inherited)",
    "OTHER_LDFLAGS": "-fapplication-extension -e_ProExtensionMain -lProExtension",
    "FRAMEWORK_SEARCH_PATHS": "/Library/Frameworks $(inherited)",
    "LIBRARY_SEARCH_PATHS": "/usr/lib $(inherited)",
    "SWIFT_OBJC_BRIDGING_HEADER": "$SRCROOT/Workflow/Workflow-Bridging-Header.h",
    "HEADER_SEARCH_PATHS": "/usr/include $(inherited)",
]

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .macOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: .default,
            sources: "App/**",
            dependencies: [.target(name: "Workflow")]
        ),
        Target(
            name: "Workflow",
            platform: .macOS,
            product: .appExtension,
            bundleId: "io.tuist.app.workflow",
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
    ]
)
