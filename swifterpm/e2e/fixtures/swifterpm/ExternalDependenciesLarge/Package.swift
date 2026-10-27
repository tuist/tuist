// swift-tools-version:5.7
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    public extension Array where Element == Configuration {
        static func spmConfigurations() -> [Configuration] {
            [
                .release(name: "Prod"),
                .debug(name: "Stage Debug"),
            ]
        }
    }

    let packageSettings: PackageSettings = {
        let frameworkType: ProjectDescription.Product = useStaticLinking ? .staticFramework : .framework
        return PackageSettings(
            productTypes: [
                // Pointfree
                "ComposableArchitecture": frameworkType,
                // Collections https://github.com/apple/swift-collections/blob/main/Package.swift
                "Collections": frameworkType,
                "BitCollections": frameworkType,
                "DequeModule": frameworkType,
                "HashTreeCollections": frameworkType,
                "HeapModule": frameworkType,
                "OrderedCollections": frameworkType,
                "_RopeModule": frameworkType,
                "SortedCollections": frameworkType,
                // CombineSchedulers https://github.com/pointfreeco/combine-schedulers/blob/main/Package.swift
                "CombineSchedulers": frameworkType,
                "ConcurrencyExtras": frameworkType,
                "IssueReporting": frameworkType,
                // CasePaths https://github.com/pointfreeco/swift-case-paths/blob/main/Package.swift
                "CasePaths": frameworkType,
                "CasePathsCore": frameworkType,
                // CustomDump https://github.com/pointfreeco/swift-custom-dump/blob/main/Package.swift
                "CustomDump": frameworkType,
                "XCTestDynamicOverlay": frameworkType,
                // Dependencies https://github.com/pointfreeco/swift-dependencies/blob/main/Package.swift
                "Dependencies": frameworkType,
                // `Dependencies` dependencies
                "Clocks": frameworkType,
                // IdentifiedCollections https://github.com/pointfreeco/swift-identified-collections/blob/main/Package.swift
                "IdentifiedCollections": frameworkType,
                // SwiftNavigation https://github.com/pointfreeco/swift-navigation/blob/main/Package.swift
                "SwiftNavigation": frameworkType,
                "SwiftUINavigation": frameworkType,
                "UIKitNavigation": frameworkType,
                "AppKitNavigation": frameworkType,
                // Perception https://github.com/pointfreeco/swift-perception/blob/main/Package.swift
                "Perception": frameworkType,
                "PerceptionCore": frameworkType,
                // Sharing https://github.com/pointfreeco/swift-sharing/blob/main/Package.swift
                "Sharing": frameworkType,
                "Sharing1": frameworkType,
                "Sharing2": frameworkType,
                // Realm
                "Realm": frameworkType,
                "RealmSwift": frameworkType,
                // GRDB
                "GRDB": frameworkType,
                //  Others
                "Algorithms": frameworkType,
                "Amplify": frameworkType,
                "AsyncAlgorithms": frameworkType,
                "InternalCollectionsUtilities": frameworkType,
                "JOSESwift": frameworkType,
                "Lottie": frameworkType,
                "OHHTTPStubs": .framework, // Tests won't work if this is static
                "Pulse": frameworkType,
                "SDWebImage": frameworkType,
                "SnapKit": frameworkType,
                "_CollectionsUtilities": frameworkType,
                "_LottieStub": frameworkType,
                "Veriff": frameworkType,
            ],
            baseSettings: .settings(configurations: .spmConfigurations()),
            targetSettings: [
                // Support for Amplify
                "Amplify": [
                    // Based on https://github.com/tuist/tuist/issues/5320#issuecomment-1771684714
                    "GENERATE_MASTER_OBJECT_FILE": "YES",
                ],
                "AmplifyBigInteger": [
                    "OTHER_SWIFT_FLAGS": "-Xcc -Wno-error=non-modular-include-in-framework-module",
                    "HEADER_SEARCH_PATHS": .array([
                        "$(inherited)",
                        "$(SRCROOT)/AmplifyPlugins/Auth/Sources/libtommath/include",
                    ]),
                ],
                "SwiftNavigation": [
                    "OTHER_SWIFT_FLAGS": .array([
                        "$(inherited)",
                        "-package-name",
                        "swift-navigation",
                    ]),
                ],
                // Module aliasing to avoid conflict with Apple's private Sharing.framework
                // See: https://github.com/pointfreeco/swift-sharing/issues/150
                "Sharing": [
                    "PRODUCT_NAME": "SwiftSharing",
                    "OTHER_SWIFT_FLAGS": .array([
                        "$(inherited)",
                        "-module-alias",
                        "Sharing=SwiftSharing",
                    ]),
                ],
                "ComposableArchitecture": [
                    "OTHER_SWIFT_FLAGS": .array([
                        "$(inherited)",
                        "-module-alias",
                        "Sharing=SwiftSharing",
                    ]),
                ],
            ]
        )
    }()
#endif

let dependencies: [PackageDescription.Package.Dependency] = [
    // ActiveLabel
    .package(url: "https://github.com/optonaut/ActiveLabel.swift", exact: "1.1.5"),

    // Alamofire
    .package(url: "https://github.com/Alamofire/Alamofire", exact: "4.9.0"),
    // Down
    .package(url: "https://github.com/johnxnguyen/Down", exact: "0.11.0"),
    // Google Maps
    .package(url: "https://github.com/googlemaps/ios-maps-sdk", exact: "9.1.1"),

    // Firebase
    .package(url: "https://github.com/google/abseil-cpp-binary", exact: "1.2024011601.1"),
    .package(url: "https://github.com/google/GoogleAppMeasurement", exact: "10.24.0"),
    .package(url: "https://github.com/google/GoogleDataTransport", exact: "9.3.0"),
    .package(url: "https://github.com/google/GoogleUtilities", exact: "7.13.0"),
    .package(url: "https://github.com/google/grpc-binary", exact: "1.62.2"),
    .package(url: "https://github.com/google/gtm-session-fetcher", exact: "3.3.0"),
    .package(url: "https://github.com/firebase/leveldb", exact: "1.22.2"),
    .package(url: "https://github.com/firebase/nanopb", exact: "2.30909.0"),
    .package(url: "https://github.com/google/promises", exact: "2.3.1"),
    .package(url: "https://github.com/apple/swift-protobuf", exact: "1.20.3"),
    .package(url: "https://github.com/google/app-check", exact: "10.19.2"),
    .package(url: "https://github.com/google/interop-ios-for-google-sdks", exact: "100.0.0"),
    .package(url: "https://github.com/SnapKit/SnapKit", exact: "5.6.0"),

    // GoogleSignIn
    .package(url: "https://github.com/google/GoogleSignIn-iOS", exact: "7.1.0"),
    .package(url: "https://github.com/openid/AppAuth-iOS", exact: "1.7.6"),
    .package(url: "https://github.com/google/GTMAppAuth", exact: "4.1.1"),

    // GRDB
    .package(url: "https://github.com/groue/GRDB.swift", exact: "7.8.0"),

    // JOSESwift
    .package(url: "https://github.com/airsidemobile/JOSESwift", exact: "2.4.0"),
    // Lottie
    .package(url: "https://github.com/airbnb/lottie-spm", exact: "4.6.0"),
    // NYTPhotoViewer
    .package(url: "https://github.com/nytimes/NYTPhotoViewer", exact: "5.0.6"),
    .package(url: "https://github.com/SDWebImage/libwebp-Xcode", exact: "1.3.2"),
    .package(url: "https://github.com/pinterest/PINCache", exact: "3.0.3"),
    .package(url: "https://github.com/pinterest/PINOperation", exact: "1.2.2"),
    .package(url: "https://github.com/pinterest/PINRemoteImage", exact: "3.0.3"),

    // OHHTTPStubs
    .package(url: "https://github.com/AliSoftware/OHHTTPStubs", exact: "9.0.0"),
    // Pulse
    .package(url: "https://github.com/kean/Pulse", exact: "3.0.0"),

    // Realm
    .package(url: "https://github.com/realm/realm-swift", exact: "10.54.5"),
    .package(url: "https://github.com/realm/realm-core", exact: "14.14.0"),

    // Stripe
    .package(url: "https://github.com/stripe/stripe-ios", exact: "25.9.0"),
    .package(url: "https://github.com/stripe/stripe-terminal-ios", exact: "5.1.1"),

    // SnapshotTesting
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.18.4"),
    .package(url: "https://github.com/apple/swift-collections", exact: "1.2.0"),
    // Amplify
    .package(url: "https://github.com/aws-amplify/amplify-swift", exact: "2.49.1"),
    .package(url: "https://github.com/aws-amplify/amplify-swift-utils-notifications", exact: "1.1.1"),
    .package(url: "https://github.com/awslabs/aws-crt-swift", exact: "0.48.0"),
    .package(url: "https://github.com/awslabs/aws-sdk-swift", exact: "1.2.59"),
    .package(url: "https://github.com/awslabs/smithy-swift", exact: "0.125.0"),
    .package(url: "https://github.com/stephencelis/SQLite.swift", exact: "0.15.3"),
    .package(url: "https://github.com/apple/swift-log", exact: "1.6.3"),
    .package(url: "https://github.com/aws-amplify/amplify-ui-swift-liveness", exact: "1.4.2"),

    // Sentry
    .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "8.57.0"),

    // Point-Free
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", exact: "1.8.0"),
    .package(url: "https://github.com/pointfreeco/combine-schedulers", exact: "1.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
    .package(url: "https://github.com/pointfreeco/swift-clocks", exact: "1.0.6"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.23.1"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", exact: "1.3.2"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", exact: "1.3.3"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections", exact: "1.1.1"),
    .package(url: "https://github.com/pointfreeco/swift-navigation", exact: "2.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.9"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", exact: "2.7.4"),

    .package(url: "https://github.com/groue/GRDBSnapshotTesting", exact: "0.4.2"),

    // SwiftSyntax
    .package(url: "https://github.com/swiftlang/swift-syntax", exact: "600.0.1"),

    // Plaid
    .package(url: "https://github.com/plaid/plaid-link-ios", exact: "6.2.0"),

    // swift-algorithms
    .package(url: "https://github.com/apple/swift-algorithms", exact: "1.2.1"),
    .package(url: "https://github.com/apple/swift-numerics", exact: "1.0.3"),

    // swift-async-algorithms
    .package(url: "https://github.com/apple/swift-async-algorithms", exact: "1.0.1"),
    // Veriff
    .package(url: "https://github.com/Veriff/veriff-ios-spm", exact: "10.2.0"),
]

let dependenciesThatProcessUserData: [PackageDescription.Package.Dependency] = [
    // Adjust
    .package(url: "https://github.com/adjust/ios_sdk", exact: "5.4.0"),
    .package(url: "https://github.com/adjust/adjust_signature_sdk", exact: "3.35.2"),

    // Braze
    .package(url: "https://github.com/braze-inc/braze-swift-sdk-prebuilt-static", exact: "14.0.4"),
    .package(url: "https://github.com/SDWebImage/SDWebImage", exact: "5.21.0"),

    // Firebase analytics
    .package(url: "https://github.com/firebase/firebase-ios-sdk", exact: "10.24.0"),
]

let package = Package(
    name: "App",
    dependencies: [dependencies + dependenciesThatProcessUserData].flatMap { $0 }
)
