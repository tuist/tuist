// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        baseSettings: .targetSettings,
        targetSettings: [
            "LookinServer": .settings(
                configurations: [
                    .debug(
                        name: "Debug",
                        settings: ["ACTIVE_COMPILATION_CONDITIONS": "$(inherited) LOOKIN_SERVER"]
                    ),
                ]
            ),
        ],
        projectOptions: [
            "LocalSwiftPackage": .options(disableSynthesizedResourceAccessors: false),
        ],
        includeLocalPackageTestTargets: true
    )
#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/ZipArchive/ZipArchive", .upToNextMajor(from: "2.5.5")),
        .package(url: "https://github.com/jpsim/Yams", .upToNextMajor(from: "5.0.6")),
        .package(url: "https://github.com/google/GoogleSignIn-iOS", .upToNextMajor(from: "7.0.0")),
        .package(
            url: "https://github.com/CocoaLumberjack/CocoaLumberjack", .upToNextMajor(from: "3.8.4")
        ),
        .package(url: "https://github.com/facebook/zstd", exact: "1.5.5"),
        .package(
            url: "https://github.com/microsoft/appcenter-sdk-apple", .upToNextMajor(from: "5.0.4")
        ),
        // Has SWIFTPM_MODULE_BUNDLE
        .package(url: "https://github.com/Quick/Quick", exact: "7.4.0"),
        .package(url: "https://github.com/Quick/Nimble", exact: "13.2.0"),
        .package(url: "https://github.com/SVProgressHUD/SVProgressHUD", exact: "2.3.1"),
        // Has missing resources and its own resource bundle accessors
        .package(url: "https://github.com/braze-inc/braze-swift-sdk.git", exact: "8.4.0"),
        // Has an umbrella header where moduleName must be sanitized
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads",
            from: "11.1.0"
        ),
        .package(url: "https://github.com/apple/swift-testing", .upToNextMajor(from: "0.6.0")),
        .package(path: "../LocalSwiftPackage"),
        .package(path: "../StringifyMacro"),
        .package(url: "https://github.com/kishikawakatsumi/UICKeyChainStore", exact: "2.2.1"),
        .package(url: "https://github.com/QMUI/LookinServer", from: "1.2.8"),
        // Has XCTest API in a non-test target. Tuist will add Test Search path to support it
        .package(url: "https://github.com/Brightify/Cuckoo.git", exact: "1.10.4"),
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
