// swift-tools-version: 5.9
import PackageDescription

// swiftlint:disable all

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [
        // === Existing entries ===
        "LumberjackWrapper": .framework,
        "CocoaLumberjack": .framework,
        "CocoaLumberjackSwift": .framework,
        // Lottie as framework - processed once and shared across all dependent targets
        "Lottie": .framework,
        // AppsFlyer and Facebook xcframeworks - configure as framework to prevent duplicate processing
        "AppsFlyerLib": .framework,
        "AppsFlyerLib-Dynamic": .framework,
        "FBAEMKit": .framework,
        "FBSDKCoreKit": .framework,
        "FBSDKCoreKit_Basics": .framework,
        // Braze xcframeworks - prevent duplicate XCFramework processing
        "BrazeLocation": .framework,
        "BrazeNotificationService": .framework,
        "BrazePushStory": .framework,
        // Google Mobile Ads xcframeworks - prevent duplicate XCFramework processing
        "GoogleAdsOnDeviceConversion": .framework,
        "MetaAdapter": .framework,
        "UID2": .framework,
        "UID2GMAPlugin": .framework,
        "GoogleAppMeasurement": .framework,
        "GoogleAppMeasurementIdentitySupport": .framework,
        // Firebase gRPC binaries - prevent duplicate XCFramework processing
        // These are C++ XCFrameworks from Firebase's grpc-binary and abseil-cpp-binary dependencies
        "grpc": .framework,
        "grpcpp": .framework,
        "openssl_grpc": .framework,
        "absl": .framework,

        // === Fix static linking warnings ===
        // When multiple targets depend on the same static library, Tuist warns about
        // duplicate symbols. Setting these to .framework uses dynamic linking instead.

        // Swift Atomics and internal targets
        "_AtomicsShims": .framework,
        "_LottieStub": .framework,
        "_NIOBase64": .framework,
        "_NIODataStructures": .framework,
        "Atomics": .framework,

        "QRCode": .framework,

        // Analytics
        "Amplitude": .framework,
        "AmplitudeContract": .framework,
        "AnalyticsConnector": .framework,
        "AmplitudeSwift": .framework,

        // Swift Async/Concurrency
        "AsyncAlgorithms": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ConcurrencyExtras": .framework,

        // Branch SDK
        "BranchSDK": .framework,

        // Braze UI
        "BrazeUI": .framework,

        // PointFree Dependencies
        "CasePathsCore": .staticFramework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "IdentifiedCollections": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "NonEmpty": .framework,
        "PerceptionCore": .framework,
        "SnapshotTesting": .framework,
        "XCTestDynamicOverlay": .framework,

        // Navigation (PointFree)
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "UIKitNavigationShim": .framework,

        // gRPC and networking
        "CGRPCZlib": .framework,
        "GRPC": .framework,
        "Gzip": .framework,
        "Logging": .framework,
        "SwiftProtobuf": .framework,

        // NIO (Swift networking)
        "CNIOAtomics": .framework,
        "CNIOBoringSSL": .framework,
        "CNIOBoringSSLShims": .framework,
        "CNIODarwin": .framework,
        "CNIOLinux": .framework,
        "CNIOLLHTTP": .framework,
        "CNIOWASI": .framework,
        "CNIOWindows": .framework,
        "NIO": .framework,
        "NIOConcurrencyHelpers": .framework,
        "NIOCore": .framework,
        "NIOEmbedded": .framework,
        "NIOExtras": .framework,
        "NIOFoundationCompat": .framework,
        "NIOHPACK": .framework,
        "NIOHTTP1": .framework,
        "NIOHTTP2": .framework,
        "NIOPosix": .framework,
        "NIOSSL": .framework,
        "NIOTLS": .framework,
        "NIOTransportServices": .framework,

        // MQTT
        "CocoaMQTT": .framework,
        "MqttCocoaAsyncSocket": .framework,

        // Crypto
        "CryptoSwift": .framework,
        "SwiftASN1": .framework,

        // Datadog
        "DatadogCore": .framework,
        "DatadogInternal": .framework,
        "DatadogPrivate": .framework,
        "DatadogRUM": .framework,
        "DatadogSDKTesting": .framework,
        "Sentry": .framework,

        // Swift Collections
        "DequeModule": .framework,
        "HeapModule": .framework,
        "InternalCollectionsUtilities": .framework,
        "OrderedCollections": .framework,

        // Facebook
        "FBAudienceNetwork": .framework,
        "FacebookAEM": .framework,
        "FacebookCore": .framework,
        "FBLPromises": .framework,
        "FBSDKGamingServicesKit": .framework,
        "FBSDKLoginKit": .framework,
        "FBSDKShareKit": .framework,
        "Promises": .framework,

        // Firebase
        "Firebase": .framework,
        "FirebaseAnalytics": .framework,
        "FirebaseAppDistribution-Beta": .framework,
        "FirebaseAppCheckInterop": .framework,
        "FirebaseCore": .framework,
        "FirebaseCoreExtension": .framework,
        "FirebaseCoreInternal": .framework,
        "FirebaseCrashlytics": .framework,
        "FirebaseCrashlyticsSwift": .framework,
        "FirebaseInstallations": .framework,
        "FirebaseMessaging": .framework,
        "FirebasePerformance": .framework,
        "FirebaseRemoteConfig": .framework,
        "FirebaseRemoteConfigInterop": .framework,
        "FirebaseABTesting": .framework,
        "FirebaseRemoteConfigInternal": .framework,
        "FirebaseAnalyticsIdentitySupport": .framework,
        "FirebaseSessions": .framework,
        "FirebaseSessionsObjC": .framework,
        "FirebaseSharedSwift": .framework,
        "GoogleDataTransport": .framework,
        "GoogleUtilities-Environment": .framework,
        "GoogleUtilities-Logger": .framework,
        "GoogleUtilities-NSData": .framework,
        "GoogleUtilities-UserDefaults": .framework,
        "GoogleUtilities-AppDelegateSwizzler": .framework,
        "GoogleUtilities-MethodSwizzler": .framework,
        "GoogleUtilities-Network": .framework,
        "GoogleUtilities-Reachability": .framework,
        "nanopb": .framework,

        // Maps
        "GISTools": .framework,
        "H3": .framework,
        "MVTTools": .framework,
        "UnifiedMapsKit": .framework,

        // UI Libraries
        "IGListKit": .framework,
        "SDWebImage": .framework,
        "SDWebImageSVGCoder": .framework,
        "SDWebImageSwiftUI": .framework,
        "SimpleToast": .framework,
        "SnapKit": .framework,

        // RxSwift
        "RxCocoa": .framework,
        "RxCocoaRuntime": .framework,
        "RxRelay": .framework,

        // Phone number
        "libPhoneNumber": .framework,
        "PhoneNumberKit": .framework,

        // Statsig
        "Statsig": .framework,

        // Ads
        "AdaEmbedFramework": .framework,
        "AppHarbrSDK": .framework,
        "AppLovinSDK": .framework,
        "BrazeKitResources": .framework,
        "FluentAdFlowAdsWidget": .framework,
        "OMSDK_Prebidorg": .framework,
        "Life360AdsSDK": .framework,
        "Life360AdsSDKGAMEventHandlers": .framework,
        "NiftCardFlow": .framework,
        "NiftCardFlowSource": .framework,
        "RollbarNotifier": .framework,

        // Arity (Driving)
        "ArityCoreEngine": .framework,
        "Capture": .framework,
        "CoreEngine": .framework,

        // Identity verification
        "Persona2": .framework,

        // Financial Services (Plaid)
        "LinkKit": .framework,

        // Zendesk
        "CommonUISDK": .framework,
        "MessagingAPI": .framework,
        "MessagingSDK": .framework,
        "SDKConfigurations": .framework,
        "SupportProvidersSDK": .framework,
        "SupportSDK": .framework,
        "ZendeskCoreSDK": .framework,

        // Timezone
        "S2GeometrySwift": .framework,
        "SwiftTimeZoneLookup": .framework,

        // System/Third-party
        "system-zlib": .framework,
        "third-party-IsAppEncrypted": .framework,
    ],
    baseSettings: .settings(configurations: [
        .debug(name: "Debug"),
        .debug(name: "Debug_IAP"),
        .debug(name: "Debug_Production"),
        .debug(name: "DebugEnterpriseQA"),
        .release(name: "Production"),
        .release(name: "Release_Enterprise"),
    ]),
    targetSettings: [
        "GRPC": .settings(base: [
            "PRODUCT_NAME": "GRPCSwift",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "GRPC=GRPCSwift"],
        ]),
        "NiftCardFlow": .settings(base: [
            "PRODUCT_MODULE_NAME": "NiftCardFlow",
            "PRODUCT_NAME": "NiftCardFlow",
        ]),
    ]
)
#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        // Local Ada SDK wrapper
        .package(path: "../AdaSDK"),

        // Swift tooling
        .package(url: "https://github.com/swiftlang/swift-syntax", .upToNextMajor(from: "602.0.0")),

        // Point-Free Dependencies
        .package(url: "https://github.com/apple/swift-async-algorithms", .upToNextMinor(from: "1.0.0")),
        .package(url: "https://github.com/apple/swift-collections", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", .upToNextMinor(from: "1.10.0")),
        .package(url: "https://github.com/pointfreeco/combine-schedulers", .upToNextMinor(from: "1.0.2")),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", .upToNextMinor(from: "1.3.0")),
        .package(url: "https://github.com/pointfreeco/swift-navigation", .upToNextMinor(from: "2.6.0")),
        .package(url: "https://github.com/pointfreeco/swift-nonempty", .upToNextMinor(from: "0.5.0")),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", .upToNextMinor(from: "1.8.0")),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", .upToNextMinor(from: "1.7.2")),
        .package(url: "https://github.com/pointfreeco/swift-clocks", .upToNextMinor(from: "1.0.6")),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.24.1"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", exact: "1.3.3"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", .upToNextMinor(from: "1.1.1")),
        .package(url: "https://github.com/pointfreeco/swift-perception", .upToNextMinor(from: "2.0.9")),
        .package(url: "https://github.com/pointfreeco/swift-sharing", .upToNextMinor(from: "2.8.0")),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.18.7"),

        // Analytics & Monitoring
        .package(url: "https://github.com/DataDog/dd-sdk-swift-testing", .upToNextMinor(from: "2.5.1")),
        .package(url: "https://github.com/DataDog/dd-sdk-ios.git", .upToNextMinor(from: "2.24.0")),
        .package(url: "https://github.com/statsig-io/statsig-kit", exact: "1.62.5"),
        .package(url: "https://github.com/amplitude/Amplitude-iOS", .upToNextMinor(from: "8.14.0")),
        .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.13.0"),
        .package(url: "https://github.com/amplitude/Amplitude-Swift", .upToNextMajor(from: "1.18.2")),

        // Firebase
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", .upToNextMinor(from: "12.6.0")),

        // Ad & Marketing
        .package(url: "https://github.com/FluentCo/Fluent-AdFlow-Widget-Package", .upToNextMinor(from: "2.0.0")),
        .package(url: "https://github.com/BranchMetrics/ios-branch-sdk-spm", .upToNextMinor(from: "3.10.0")),
        .package(url: "https://github.com/AppsFlyerSDK/AppsFlyerFramework-Dynamic", .upToNextMinor(from: "6.17.9")),
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", .upToNextMinor(from: "12.0.0")),
        .package(url: "https://github.com/GeoEdgeSDK/AppHarbrSDK", exact: "1.29.2"),
        .package(url: "https://github.com/IABTechLab/uid2-ios-plugin-google-gma", .upToNextMinor(from: "2.0.2")),

        // Architecture & UI
        .package(url: "https://github.com/dagronf/QRCode", exact: "28.0.2"),
        .package(url: "https://github.com/ReactiveX/RxSwift", .upToNextMinor(from: "6.5.0")),
        .package(url: "https://github.com/SnapKit/SnapKit", .upToNextMinor(from: "5.7.1")),
        .package(url: "https://github.com/airbnb/lottie-spm", .upToNextMinor(from: "4.5.0")),

        // Financial Services
        .package(url: "https://github.com/plaid/plaid-link-ios-spm.git", exact: "6.4.3"),

        // Social & Communication
        .package(url: "https://github.com/facebook/facebook-ios-sdk.git", .upToNextMinor(from: "18.0.1")),
        .package(url: "https://github.com/braze-inc/braze-swift-sdk", .upToNextMinor(from: "9.0.0")),
        .package(url: "https://github.com/persona-id/inquiry-ios-2.git", .upToNextMinor(from: "2.15.0")),
        .package(url: "https://github.com/zendesk/support_sdk_ios", .upToNextMinor(from: "8.0.2")),

        // Utilities
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack", .upToNextMinor(from: "3.8.5")),
        .package(url: "https://github.com/SDWebImage/SDWebImage", .upToNextMinor(from: "5.21.1")),
        .package(url: "https://github.com/SDWebImage/SDWebImageSVGCoder", .upToNextMinor(from: "1.7.0")),
        .package(url: "https://github.com/SDWebImage/SDWebImageSwiftUI", .upToNextMinor(from: "3.1.4")),
        .package(url: "https://github.com/emqx/CocoaMQTT", .upToNextMinor(from: "2.1.6")),
        .package(url: "https://github.com/httpswift/swifter", exact: "1.5.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", exact: "1.8.3"),

        // Networking (gRPC & NIO)
        .package(url: "https://github.com/grpc/grpc-swift", .upToNextMinor(from: "1.24.2")),
        .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMinor(from: "1.33.1")),
        .package(url: "https://github.com/apple/swift-nio", .upToNextMinor(from: "2.79.0")),
        .package(url: "https://github.com/apple/swift-nio-http2", .upToNextMinor(from: "1.35.0")),
        .package(url: "https://github.com/apple/swift-log", .upToNextMinor(from: "1.6.2")),
        .package(url: "https://github.com/apple/swift-atomics", .upToNextMinor(from: "1.2.0")),

        // Observability
        .package(url: "https://github.com/bitdriftlabs/capture-ios.git", from: "0.19.1"),

        // S2 Geometry
        .package(url: "https://github.com/philip-bui/s2-geometry-swift.git", from: "1.0.3"),

        // Timezone
        .package(url: "https://github.com/patrick-zippenfenig/SwiftTimeZoneLookup", from: "1.0.7")
    ]
)
