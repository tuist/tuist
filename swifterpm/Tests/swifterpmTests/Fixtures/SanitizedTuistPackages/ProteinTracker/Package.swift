// swift-tools-version: 6.3

import PackageDescription

#if TUIST
import ProjectDescription

enum ProteinTrackerPackageLinking: String {
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

let linkableProductNames: Set<String> = [
  "_NumericsShims",
  "AccessibilityDependency",
  "Algorithms",
  "ApplicationDependency",
  "AsyncAlgorithms",
  "BundleDependency",
  "CasePaths",
  "CasePathsCore",
  "Clocks",
  "CodableDependency",
  "CombineSchedulers",
  "ComposableArchitecture",
  "CompressionDependency",
  "ConcurrencyExtras",
  "CustomDump",
  "DataDependency",
  "Dependencies",
  "DependenciesAdditions",
  "DependenciesAdditionsBasics",
  "DependenciesTestSupport",
  "DeviceDependency",
  "GRDB",
  "IdentifiedCollections",
  "InternalCollectionsUtilities",
  "IssueReporting",
  "IssueReportingPackageSupport",
  "IssueReportingTestSupport",
  "LoggerDependency",
  "NotificationCenterDependency",
  "OrderedCollections",
  "PathDependency",
  "Perception",
  "PerceptionCore",
  "PersistentContainerDependency",
  "ProcessInfoDependency",
  "RealModule",
  "RevenueCat",
  "RevenueCatUI",
  "Sharing",
  "Sharing1",
  "Sharing2",
  "SQLite3",
  "SQLite3Client",
  "SQLiteData",
  "SQLiteDataClient",
  "SQLiteDataClientLive",
  "StructuredQueries",
  "StructuredQueriesCore",
  "StructuredQueriesSQLiteCore",
  "SwiftNavigation",
  "SwiftUINavigation",
  "SwiftUINavigationCore",
  "Tagged",
  "UIKitNavigation",
  "UIKitNavigationShim",
  "UserDefaultsDependency",
  "UserNotificationsDependency",
  "UUIDV7",
  "WhatsNewKit",
  "XCTestDynamicOverlay",
]

let staticOnlyProductNames: Set<String> = []

let dynamicOnlyProductNames: Set<String> = []

func packageProductTypes(
  for linking: ProteinTrackerPackageLinking
) -> [String: ProjectDescription.Product] {
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

let packageSettings = PackageSettings(
  productTypes: packageProductTypes(for: ProteinTrackerPackageLinking.current),
  baseSettings: .settings(
    base: .init()
      .swiftVersion("6.3")
      .enableUpcomingFeature("NonisolatedNonsendingByDefault")
      .enableUpcomingFeature("InferIsolatedConformances")
      .enableUpcomingFeature("InferSendableFromCaptures")
      .enableUpcomingFeature("DisableOutwardActorInference")
      .enableUpcomingFeature("GlobalActorIsolatedTypesUsability")
      .enableUpcomingFeature("RegionBasedIsolation"),
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
    "Sharing": .settings(
      base: [
        "PRODUCT_NAME": "PFSharing",
        "PRODUCT_NAME[sdk=iphoneos*]": "PFSharing",
        "PRODUCT_NAME[sdk=iphonesimulator*]": "PFSharing",
      ]
      .otherSwiftFlags(["-module-alias", "Sharing=PFSharing"])
    ),
  ]
)

extension ProjectDescription.SettingsDictionary {
  func enableUpcomingFeature(_ feature: String) -> ProjectDescription.SettingsDictionary {
    merging(["SWIFT_UPCOMING_FEATURE_\(feature.uppercased())": "YES"])
  }
}

#endif

// MARK: Package

let package = Package(
  name: "PackageName",
  platforms: [
    .iOS("18.0"),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.8.0"),
    .package(
      url: "https://github.com/pointfreeco/swift-composable-architecture",
      from: "1.25.5",
      traits: [
        "ComposableArchitecture2Deprecations",
        // "ComposableArchitecture2DeprecationOverloads"
      ]
    ),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
    .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
    .package(url: "https://github.com/tgrapperon/swift-dependencies-additions", branch: "xcode26"),
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.4.1", traits: ["SQLiteDataTagged"]),
    .package(
      url: "https://github.com/mhayes853/swift-uuidv7",
      from: "0.5.0",
      traits: [
        "SwiftUUIDV7SQLiteData",
        "SwiftUUIDV7Dependencies",
        "SwiftUUIDV7Tagged",
      ]
    ),
    .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.1"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.1.3", traits: []),
    .package(url: "https://github.com/SvenTiigi/WhatsNewKit.git", from: "2.2.1"),
    .package(url: "https://github.com/lzell/AIProxySwift", from: "0.150.0"),
    .package(url: "https://github.com/RevenueCat/purchases-ios-spm", from: "5.72.0"),
    .package(url: "https://github.com/EmergeTools/Pow", from: "1.0.6")
  ]
)
