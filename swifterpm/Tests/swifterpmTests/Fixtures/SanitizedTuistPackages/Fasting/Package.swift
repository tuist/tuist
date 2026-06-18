// swift-tools-version: 6.1

import PackageDescription

#if TUIST
  import ProjectDescription

  enum FastyPackageLinking: String {
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
    "AccessibilityDependency",
    "Algorithms",
    "ApplicationDependency",
    "AsyncAlgorithms",
    "BitCollections",
    "BundleDependency",
    "CasePaths",
    "Clocks",
    "CodableDependency",
    "Collections",
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
    "DequeModule",
    "DeviceDependency",
    "Ensembles",
    "EnsemblesCloudKit",
    "HashTreeCollections",
    "HeapModule",
    "IdentifiedCollections",
    "InlineSnapshotTesting",
    "InternalCollectionsUtilities",
    "IssueReporting",
    "IssueReportingPackageSupport",
    "Kronos",
    "Localized",
    "LoggerDependency",
    "NotificationCenterDependency",
    "OrderedCollections",
    "PathDependency",
    "Perception",
    "PerceptionCore",
    "PersistentContainerDependency",
    "Pow",
    "ProcessInfoDependency",
    "RealModule",
    "Regressor",
    "RevenueCat",
    "RevenueCatUI",
    "Roadmap",
    "Sharing",
    "SnapshotTesting",
    "SnapshotTestingCustomDump",
    "SwiftNavigation",
    "SwiftUINavigation",
    "SwiftUINavigationCore",
    "Tagged",
    "UIKitNavigation",
    "UIKitNavigationShim",
    "UserDefaultsDependency",
    "UserNotificationsDependency",
    "WhatsNewKit",
    "XCTestDynamicOverlay",
    "Difference"
  ]

  let staticOnlyProductNames: Set<String> = []

  let dynamicOnlyProductNames: Set<String> = [
    "IssueReportingPackageSupport"
  ]

  func packageProductTypes(for linking: FastyPackageLinking) -> [String: ProjectDescription.Product] {
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
    //        baseSettings: .targetSettings
    productTypes: packageProductTypes(for: FastyPackageLinking.current),
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
      "Sharing": .settings(base: [
        "PRODUCT_NAME": "PFSharing",
        "PRODUCT_NAME[sdk=iphoneos*]": "PFSharing",
        "PRODUCT_NAME[sdk=iphonesimulator*]": "PFSharing",
        "PRODUCT_NAME[sdk=watchos*]": "PFSharing",
        "PRODUCT_NAME[sdk=watchsimulator*]": "PFSharing"
      ]
      .otherSwiftFlags(["-module-alias", "Sharing=PFSharing"])
      )
    ]
  )

  extension ProjectDescription.SettingsDictionary {
    func enableUpcomingFeature(_ feature: String) -> ProjectDescription.SettingsDictionary {
      merging([swiftUpcomingFeatureBuildSettingName(for: feature): "YES"])
    }

    private func swiftUpcomingFeatureBuildSettingName(for feature: String) -> String {
      let name = feature.reduce(into: "") { result, character in
        if character.isUppercase, !result.isEmpty {
          result.append("_")
        }
        result.append(contentsOf: character.uppercased())
      }

      return "SWIFT_UPCOMING_FEATURE_\(name)"
    }
  }

#endif

let package = Package(
  name: "PackageName",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
    .tvOS(.v17),
    .watchOS(.v10)
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-perception", from: "2.0.9"),
    .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.7.0"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.25.0", traits: []),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.7"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.7.4"),
    .package(url: "https://github.com/pointfreeco/combine-schedulers", from: "1.1.0", traits: []),

    .package(url: "https://github.com/tgrapperon/swift-dependencies-additions", branch: "xcode26"),
    .package(url: "https://github.com/mentalfaculty/ensembles-next", exact: "2.13.0"),
    .package(url: "https://github.com/apple/swift-algorithms", from: "1.0.1"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.1.4", traits: []),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.5"),
    .package(url: "https://github.com/SvenTiigi/WhatsNewKit.git", from: "2.1.0"),
    .package(url: "https://github.com/AvdLee/Roadmap", branch: "main"),
    .package(url: "https://github.com/krzysztofzablocki/Difference.git", from: "1.0.2"),
    .package(url: "https://github.com/openalloc/SwiftRegressor", from: "1.2.3"),
    .package(url: "https://github.com/RevenueCat/purchases-ios-spm", from: "5.47.1"),
    .package(url: "https://github.com/EmergeTools/Pow", branch: "main"),
    .package(url: "https://github.com/KaiOelfke/Kronos", branch: "main"),
    .package(url: "https://github.com/kaioelfke/swift-macro-localized/", branch: "develop"),
    .package(url: "https://github.com/KaiOelfke/AsyncCompatibilityKit", branch: "main")
  ]
)
