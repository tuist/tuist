import ProjectDescription

let project = Project(
  name: "MyApp",
  targets: [
    iosTargetWithUniversalFramework(),
    macOSTargetWithUniversalFramework(),
    tvOSTargetWithUniversalFramework(),
    watchOSTargetWithUniversalFramework(),
    multiTargetsFramework(),
    multiTargetsFrameworkTests(),
    unviversalApp(),
    unviversalAppTests()
  ]
)

func iosTargetWithUniversalFramework() -> Target {
  Target(
    name: "iOSExample",
    platform: .iOS,
    product: .app,
    bundleId: "io.tuist.ios.example",
    deploymentTarget: .iOS(targetVersion: "16.0", devices: [.ipad, .iphone]),
    sources: .paths([.relativeToManifest("Sources/**")]),
    dependencies: [.target(name: "MultiDeploymentTargetsFramework"), .zipFoundation],
    settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
  )
}

func macOSTargetWithUniversalFramework() -> Target {
  Target(
    name: "macOSExample",
    platform: .macOS,
    product: .app,
    bundleId: "io.tuist.macos.example",
    deploymentTarget: .macOS(targetVersion: "13.0"),
    sources: .paths([.relativeToManifest("Sources/**")]),
    dependencies: [.target(name: "MultiDeploymentTargetsFramework"), .zipFoundation],
    settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
  )
}

func tvOSTargetWithUniversalFramework() -> Target {
  Target(
    name: "tvOSExample",
    platform: .tvOS,
    product: .app,
    bundleId: "io.tuist.tvos.example",
    deploymentTarget: .tvOS(targetVersion: "16.0"),
    sources: .paths([.relativeToManifest("Sources/**")]),
    dependencies: [.target(name: "MultiDeploymentTargetsFramework"), .zipFoundation],
    settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
  )
}

func watchOSTargetWithUniversalFramework() -> Target {
  Target(
    name: "watchOSExample",
    platform: .watchOS,
    product: .app,
    bundleId: "io.tuist.watchos.example",
    deploymentTarget: .watchOS(targetVersion: "9.0"),
    infoPlist: .extendingDefault(
      with:
        [
          "WKWatchOnly": true,
          "WKApplication": true
        ]
    ),
    sources: .paths([.relativeToManifest("Sources/**")]),
    dependencies: [.target(name: "MultiDeploymentTargetsFramework"), .zipFoundation],
    settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
  )
}


func multiTargetsFramework() -> Target {
  Target(
    name: "MultiDeploymentTargetsFramework",
    platform: .iOS,
    product: .framework,
    bundleId: "io.tuist.multi.targets.framework",
    deploymentTargets: [
      .iOS(targetVersion: "16.0", devices: [.ipad, .iphone]),
      .macOS(targetVersion: "13.0"),
      .tvOS(targetVersion: "16.0"),
      .watchOS(targetVersion: "9.0")
    ],
    sources: .paths([.relativeToManifest("Framework/Sources/**")]),
    dependencies: [],
    settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
  )
}

func multiTargetsFrameworkTests() -> Target {
  Target(
    name: "MultiDeploymentTargetsFrameworkTests",
    platform: .iOS,
    product: .unitTests,
    bundleId: "io.tuist.multi.targets.framework.tests",
    deploymentTargets: [
      .iOS(targetVersion: "16.0", devices: [.ipad, .iphone]),
      .macOS(targetVersion: "13.0"),
      .tvOS(targetVersion: "16.0"),
      .watchOS(targetVersion: "9.0")
    ],
    infoPlist: .file(path: .relativeToManifest("Info.plist")),
    sources: .paths([.relativeToManifest("Tests/**")]),
    dependencies: [.target(name: "MultiDeploymentTargetsFramework"), .quick, .nimble],
    settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
  )
}

func unviversalApp() -> Target {
  Target(
    name: "UniversalApp",
    platform: .iOS,
    product: .app,
    bundleId: "io.tuist.ios.universal.app",
    deploymentTargets: [
      .iOS(targetVersion: "16.0", devices: [.ipad, .iphone]),
      .macOS(targetVersion: "13.0"),
      .tvOS(targetVersion: "16.0"),
      .watchOS(targetVersion: "9.0")
    ],
    sources: .paths([.relativeToManifest("Sources/**")]),
    dependencies: [.target(name: "MultiDeploymentTargetsFramework"), .zipFoundation],
    settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
  )
}

func unviversalAppTests() -> Target {
  Target(
    name: "UniversalAppTests",
    platform: .iOS,
    product: .unitTests,
    bundleId: "io.tuist.ios.universal.app",
    deploymentTargets: [
      .iOS(targetVersion: "16.0", devices: [.ipad, .iphone]),
      .macOS(targetVersion: "13.0"),
      .tvOS(targetVersion: "16.0"),
      .watchOS(targetVersion: "9.0")
    ],
    sources: .paths([.relativeToManifest("Sources/**")]),
    dependencies: [.target(name: "UniversalApp"), .quick, .nimble],
    settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
  )
}

extension TargetDependency {
  public static var zipFoundation: TargetDependency {
    .external(name: "ZIPFoundation")
  }
  
  public static var quick: TargetDependency {
    .external(name: "Quick")
  }
  
  public static var nimble: TargetDependency {
    .external(name: "Nimble")
  }
}
