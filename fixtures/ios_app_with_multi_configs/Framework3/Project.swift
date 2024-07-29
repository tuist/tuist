import ProjectDescription

func getInfoPlist(displayName: String, appQueriesSchemes: [String] = []) -> InfoPlist {
    var plistContent: [String: Plist.Value] = [
        "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "LSRequiresIPhoneOS": true,
        "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
    ]

    plistContent["CFBundleDisplayName"] = .string(displayName)

    if !appQueriesSchemes.isEmpty {
        plistContent["LSApplicationQueriesSchemes"] = .array(appQueriesSchemes.map { .string($0) })
    }

    return .dictionary(plistContent)
}

let settings: Settings = .settings(
    configurations: [
        .debug(name: "Debug", xcconfig: "../ConfigurationFiles/Debug.xcconfig"),
        .release(name: "Beta", xcconfig: "../ConfigurationFiles/Beta.xcconfig"),
        .release(name: "Release", xcconfig: "../ConfigurationFiles/Release.xcconfig"),
    ]
)

// Targets can override select configurations if needed
let targetSettings: Settings = .settings(
    base: [
        "TARGET_BASE": "TARGET_BASE",
    ],
    configurations: [
        .debug(
            name: "Debug",
            infoPlist: getInfoPlist(displayName: "Framework3 Debug")
        ),
        .release(
            name: "Beta",
            infoPlist: getInfoPlist(
                displayName: "Framework3 Beta",
                appQueriesSchemes: ["googlemail", "message", "ymail"]
            )
        ),
        .release(
            name: "Release",
            xcconfig: "../ConfigurationFiles/Target.Release.xcconfig",
            infoPlist: getInfoPlist(
                displayName: "Framework3",
                appQueriesSchemes: ["googlemail", "message", "ms-outlook", "ymail"]
            )
        ),
    ]
)

let project = Project(
    name: "Framework3",
    settings: settings,
    targets: [
        .target(
            name: "Framework3",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.Framework3",
            infoPlist: nil,
            sources: "Sources/**",
            dependencies: [],
            settings: targetSettings
        ),
        .target(
            name: "Framework3Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.Framework3Tests",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework3"),
            ]
        ),
    ]
)
