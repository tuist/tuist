// swift-tools-version: 5.10
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        baseSettings: .targetSettings,
        projectOptions: [
            "LocalSwiftPackage": .options(disableSynthesizedResourceAccessors: false),
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "1.9.2")),
        .package(url: "https://github.com/ZipArchive/ZipArchive", .upToNextMajor(from: "2.5.5")),
        .package(url: "https://github.com/jpsim/Yams", .upToNextMajor(from: "5.0.6")),
        .package(url: "https://github.com/google/GoogleSignIn-iOS", .upToNextMajor(from: "7.0.0")),
        .package(url: "https://github.com/getsentry/sentry-cocoa", .upToNextMajor(from: "8.20.0")),
        .package(url: "https://github.com/realm/realm-swift", .upToNextMajor(from: "10.46.0")),
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack", .upToNextMajor(from: "3.8.4")),
        .package(url: "https://github.com/facebook/zstd", exact: "1.5.5"),
        .package(url: "https://github.com/microsoft/appcenter-sdk-apple", .upToNextMajor(from: "5.0.4")),
        // Has SWIFTPM_MODULE_BUNDLE
        .package(url: "https://github.com/tuist/NYTPhotoViewer", branch: "develop"),
        .package(url: "https://github.com/Quick/Quick", exact: "7.4.0"),
        .package(url: "https://github.com/Quick/Nimble", exact: "13.2.0"),
        .package(url: "https://github.com/SVProgressHUD/SVProgressHUD", exact: "2.3.1"),
        // Has missing resources and its own resource bundle accessors
        .package(url: "https://github.com/urbanairship/ios-library.git", .exact("17.7.3")),
        // Has an umbrella header where moduleName must be sanitized
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.2.0"),
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads", from: "11.1.0"),
        .package(url: "https://github.com/apple/swift-testing", .upToNextMajor(from: "0.6.0")),
        .package(path: "../LocalSwiftPackage"),
        .package(path: "../StringifyMacro"),
        .package(url: "https://github.com/kishikawakatsumi/UICKeyChainStore", exact: "2.2.1"),
        // Has XCTest API in a non-test target. Tuist will add Test Search path to support it
        .package(url: "https://github.com/Brightify/Cuckoo.git", exact: "1.10.4"),
    ]
)
