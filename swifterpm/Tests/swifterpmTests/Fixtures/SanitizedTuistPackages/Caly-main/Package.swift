// swift-tools-version: 6.2

import PackageDescription

#if TUIST
import ProjectDescription

enum CalyPackageLinking: String {
  case `static`
  case dynamic

  static var current: Self {
    guard case let .string(rawValue) = Environment.linking else {
      return .dynamic
    }

    guard let linking = Self(rawValue: rawValue) else {
      fatalError("Unsupported TUIST_LINKING value '\(rawValue)'. Use 'static' or 'dynamic'.")
    }

    return linking
  }
}

// Base linkage is applied to all known package products, then explicit overrides win.
let linkableProductNames: Set<String> = [
  "_NumericsShims",
  "_RopeModule",
  "Algorithms",
  "AsyncAlgorithms",
  "BitCollections",
  "CasePaths",
  "Clocks",
  "Collections",
  "CombineSchedulers",
  "ComposableArchitecture",
  "ConcurrencyExtras",
  "CustomDump",
  "Dependencies",
  "DependenciesTestSupport",
  "DequeModule",
  "HashTreeCollections",
  "HeapModule",
  "IdentifiedCollections",
  "InternalCollectionsUtilities",
  "IssueReporting",
  "IssueReportingTestSupport",
  "OrderedCollections",
  "PerceptionCore",
  "Perception",
  "RealModule",
  "SwiftUINavigation",
  "SwiftUINavigationCore",
  "SwiftNavigation",
  "Tagged",
  "XCTestDynamicOverlay",
  "IssueReportingPackageSupport",
  "SQLiteData",
  "SQLite3",
  "SQLite3Client",
  "SQLiteDataClient",
  "SQLiteDataClientLive",
  "AIProxy",
  "Sharing",
  "Sharing1",
  "Sharing2",
  "SuperwallKit",
  "Superscript",
  "UIKitNavigationShim",
  "UIKitNavigation",
  "GRDB",
  "StructuredQueries",
  "StructuredQueriesCore",
  "StructuredQueriesSQLiteCore",
  "UUIDV7",
  "UserNotificationsDependency",
  "DependenciesAdditionsBasics",
  "ColorTokensKit",
  "WhatsNewKit"
]

let staticOnlyProductNames: Set<String> = []

let dynamicOnlyProductNames: Set<String> = [
  "IssueReportingPackageSupport"
]

func packageProductTypes(for linking: CalyPackageLinking) -> [String: ProjectDescription.Product] {
  let baseType: ProjectDescription.Product = linking == .dynamic ? .framework : .staticFramework
  var productTypes = Dictionary(uniqueKeysWithValues: linkableProductNames.map { ($0, baseType) })

  for productName in staticOnlyProductNames {
    productTypes[productName] = .staticFramework
  }

  for productName in dynamicOnlyProductNames {
    productTypes[productName] = .framework
  }

  return productTypes
}

let packageSettings: PackageSettings = .init(
  productTypes: packageProductTypes(for: CalyPackageLinking.current),
  baseSettings: .settings(
    base: .init()
      .swiftVersion("6.0"),
    debug: .init()
      .swiftActiveCompilationConditions(["$(inherited)", "XCODE_$(XCODE_VERSION_MAJOR)"])
      .merging(["GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "XCODE_$(XCODE_VERSION_MAJOR)=1"]])
      .merging(["SWIFT_STRICT_CONCURRENCY": "complete"]),
    release: .init()
      .swiftActiveCompilationConditions(["$(inherited)", "XCODE_$(XCODE_VERSION_MAJOR)"])
      .merging(["GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "XCODE_$(XCODE_VERSION_MAJOR)=1"]])
      .merging(["SWIFT_STRICT_CONCURRENCY": "complete"])
  ),
  targetSettings: [
    "ComposableArchitecture": .settings(base: .init().otherSwiftFlags(["-module-alias", "Sharing=PFSharing"])),
    "SQLiteData": .settings(base: .init().otherSwiftFlags(["-module-alias", "Sharing=PFSharing"])),
    "Sharing": .settings(base: [
      "PRODUCT_NAME": "PFSharing",
      "PRODUCT_NAME[sdk=iphoneos*]": "PFSharing",
      "PRODUCT_NAME[sdk=iphonesimulator*]": "PFSharing",
      "PRODUCT_NAME[sdk=watchos*]": "PFSharing",
      "PRODUCT_NAME[sdk=watchsimulator*]": "PFSharing",
    ]
    .otherSwiftFlags(["-module-alias", "Sharing=PFSharing"])
    ),
    "SuperwallKit": .settings(base: .init().swiftVersion("5.0")),
    "WhatsNewKit": .settings(base: .init().swiftVersion("5.0")),

    "UserNotificationsDependency": .settings(base: .init().swiftVersion("5.0")),
    "AccessibilityDependency": .settings(base: .init().swiftVersion("5.0")),
    "ApplicationDependency": .settings(base: .init().swiftVersion("5.0")),
    "BundleDependency": .settings(base: .init().swiftVersion("5.0")),
    "CodableDependency": .settings(base: .init().swiftVersion("5.0")),
    "CompressionDependency": .settings(base: .init().swiftVersion("5.0")),
    "DataDependency": .settings(base: .init().swiftVersion("5.0")),
    "DependenciesAdditions": .settings(base: .init().swiftVersion("5.0")),
    "DependenciesAdditionsBasics": .settings(base: .init().swiftVersion("5.0")),
    "ColorTokensKit": .settings(base: .init().swiftVersion("5.0")),
    "DeviceDependency": .settings(base: .init().swiftVersion("5.0")),
    "LoggerDependency": .settings(base: .init().swiftVersion("5.0")),
    "NotificationCenterDependency": .settings(base: .init().swiftVersion("5.0")),
    "PathDependency": .settings(base: .init().swiftVersion("5.0")),
    "PersistentContainerDependency": .settings(base: .init().swiftVersion("5.0")),
    "ProcessInfoDependency": .settings(base: .init().swiftVersion("5.0")),
    "UserDefaultsDependency": .settings(base: .init().swiftVersion("5.0")),
  ]
)
#endif

let package = Package(
  name: "Caly",
  platforms: [
    .iOS(.v18)
  ],
  dependencies: [
    // TCA ecosystem
    .package(
      url: "https://github.com/pointfreeco/swift-composable-architecture",
      from: "1.25.5",
      traits: ["ComposableArchitecture2Deprecations"]
    ),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.1"),
    .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-perception", from: "2.0.9"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.3"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.8.0"),

    // Database
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.4.1", traits: ["SQLiteDataTagged"]),

    // UUID v7 with traits
    .package(
      url: "https://github.com/mhayes853/swift-uuidv7",
      from: "0.5.0",
      traits: [
        "SwiftUUIDV7SQLiteData",
        "SwiftUUIDV7Dependencies",
        "SwiftUUIDV7Tagged",
      ]
    ),

    // AI & Monetization
    .package(url: "https://github.com/lzell/AIProxySwift", from: "0.138.0"),
    .package(url: "https://github.com/superwall/Superwall-iOS", from: "4.11.2"),

    // Utilities
    .package(url: "https://github.com/apple/swift-collections", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.1"),

    .package(url: "https://github.com/tgrapperon/swift-dependencies-additions", branch: "xcode26"),
    .package(url: "https://github.com/metasidd/ColorTokensKit-Swift", from: "1.0.0"),
    .package(url: "https://github.com/SvenTiigi/WhatsNewKit.git", from: "2.2.1"),
  ]
)
