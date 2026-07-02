// swift-tools-version: 5.9
@preconcurrency import PackageDescription
import Foundation

#if TUIST
@preconcurrency import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [
        "DeviceKit": .framework,
        "Lottie": .framework,
        "PanModal": .framework,
        "Nuke": .framework,
        "NukeUI": .framework,
        "HTMLEntities": .framework,
        "ConfettiSwiftUI": .framework,
        "ScrollKit": .framework,
        "Dependencies": .framework,
        "Clocks": .framework,
        "ConcurrencyExtras": .framework,
        "CombineSchedulers": .framework,
        "IssueReporting": .framework,
        "XCTestDynamicOverlay": .framework,
        "Figma": .framework,
        "Atomics": .framework,
        "MultipartKit": .framework,
        "NIO": .framework,
        "CNIOAtomics": .framework,
        "CNIODarwin": .framework,
        "CNIOLinux": .framework,
        "CNIOOpenBSD": .framework,
        "CNIOWASI": .framework,
        "CNIOLLHTTP": .framework,
        "CNIOWindows": .framework,
        "NIOConcurrencyHelpers": .framework,
        "NIOHTTP1": .framework,
        "NIOCore": .framework,
        "_NIOBase64": .framework,
        "_NIODataStructures": .framework,
        "DequeModule": .framework,
        "CasePathsCore": .framework,
        "InternalCollectionsUtilities": .framework,
        "OrderedCollections": .framework,
        "Parsing": .framework,
        "URLRouting": .framework,
        "PreviewGallery": .framework,
        "SnapshotPreferences": .framework,
        "SnapshotSharedModels": .framework,
        "SnapshotPreviewsCore": .framework,

    ],
    targetSettings: [
        "_SwiftSyntaxTestSupport": .settings(
            base: ["OTHER_LDFLAGS": "$(inherited) -framework XCTest"]
        ),
        "SwiftSyntaxMacrosTestSupport": .settings(
            base: ["OTHER_LDFLAGS": "$(inherited) -framework XCTest"]
        ),
    ]
)

#endif

// To update secrets, see: https://github.com/etsy/ios-secrets-prod/blob/main/README.md
// Once you have merged your secrets to main in `ios-secrets-prod`, copy the commit hash here.
let secretsDependency = Package.Dependency.package(
    url: "git@github.com:etsy/ios-secrets-prod.git",
    revision: "9a089f5"
)

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", exact: "8.0.0"),
        .package(url: "https://github.com/devicekit/DeviceKit", exact: "5.8.0"),
        .package(url: "https://github.com/airbnb/lottie-ios.git", exact: "4.4.3"),
        .package(url: "https://github.com/etsy/PanModal", revision: "2322ef9cec54127b7ae69bbed01f8b598e35aca4"),
        .package(url: "https://github.com/jonreid/OCMockito", exact: "7.0.1"),
        .package(url: "https://github.com/ashleymills/Reachability.swift", exact: "5.2.1"),
        .package(url: "https://github.com/braze-inc/braze-swift-sdk", exact: "11.3.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "11.6.0"),
        .package(url: "https://github.com/google/GoogleUtilities", exact: "8.0.2"),
        .package(url: "https://github.com/AliSoftware/OHHTTPStubs.git", exact: "9.1.0"),
        .package(url: "https://github.com/button/button-merchant-ios", exact: "1.7.1"),
        .package(url: "https://github.com/ccgus/fmdb", exact: "2.7.9"),
        .package(url: "https://github.com/facebook/facebook-ios-sdk", exact: "18.0.3"),
        .package(url: "https://github.com/AppsFlyerSDK/AppsFlyerFramework-Static", exact: "6.16.1"),
        .package(url: "https://github.com/kean/Nuke.git", exact: "12.7.0"),
        .package(url: "https://github.com/Kitura/swift-html-entities", exact: "4.0.1"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.17.6"),
        .package(url: "https://github.com/cashapp/AccessibilitySnapshot", exact: "0.10.0"),
        .package(url: "https://github.com/qualtrics/qualtrics-digital-ios-sdk", exact: "2.22.0"),
        .package(url: "https://github.com/BranchMetrics/ios-branch-sdk-spm", exact: "3.14.0"),
        .package(url: "https://github.com/simibac/ConfettiSwiftUI.git", exact: "1.1.0"),
        .package(url: "https://github.com/nalexn/ViewInspector", exact: "0.10.0"),
        .package(url: "https://github.com/Subito-it/SBTUITestTunnel", revision: "a5aa6f417897192c677bd718fee819f5e18e656e"),
        .package(url: "https://github.com/danielsaidi/ScrollKit.git", exact: "0.5.0"),
        .package(url: "https://github.com/DataDome/datadome-ios-package", exact: "3.7.0"),
        .package(url: "https://github.com/apple/swift-syntax", exact: "600.0.1"),
        .package(url: "https://github.com/fullstorydev/fullstory-swift-package-ios", exact: "1.64.2"),
        .package(url: "https://github.com/ProxymanApp/atlantis", exact: "1.28.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.8.1"),
        .package(url: "https://github.com/apple/swift-collections", exact: "1.1.4"),
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.33.1"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.4.1"),
        .package(url: "https://github.com/pointfreeco/swift-url-routing.git", exact: "0.6.2"),
        .package(url: "https://github.com/figma/code-connect", exact: "1.3.4"),
        .package(url: "https://github.com/apple/swift-atomics.git", exact: "1.3.0"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.97.0"),
        .package(url: "https://github.com/vapor/multipart-kit.git", exact: "4.7.1"),
        .package(url: "https://github.com/EmergeTools/SnapshotPreviews", exact: "0.11.0"),
        .package(url: "https://github.com/sierra-inc/sierra-ios-sdk", exact: "0.20260515.7173715"),
        secretsDependency,
    ]
)
