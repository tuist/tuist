import ProjectDescription

let appTarget: Target = .target(
    name: "App",
    destinations: [.iPhone, .iPad, .mac, .appleWatch],
    product: .app,
    bundleId: "dev.tuist.App",
    deploymentTargets: .multiplatform(iOS: "14.0", macOS: "14.0.0", watchOS: "9.0"),
    sources: "Modules/App/Sources/**/*.swift",
    dependencies: [
        .target(name: "iOSStaticFramework", condition: .when([.ios])),
        .target(name: "WatchOSDynamicFramework", condition: .when([.watchos])),
        .target(name: "MacOSStaticFramework", condition: .when([.macos])),
    ]
)

let iOSStaticFramework: Target = .target(
    name: "iOSStaticFramework",
    destinations: [.iPhone, .iPad, .mac],
    product: .staticFramework,
    bundleId: "dev.tuist.App.iOSStaticFramework",
    deploymentTargets: .multiplatform(iOS: "14.0"),
    sources: "Modules/iOSStaticFramework/Sources/**/*.swift",
    resources: "Modules/iOSStaticFramework/Resources/**",
    dependencies: [
        .target(name: "MultiPlatformTransitiveDynamicFramework", condition: .when([.ios, .macos])),
    ]
)

let watchOSDynamicFramework: Target = .target(
    name: "WatchOSDynamicFramework",
    destinations: [.appleWatch],
    product: .framework,
    bundleId: "dev.tuist.App.WatchOSDynamicFramework",
    deploymentTargets: .multiplatform(watchOS: "9.0"),
    sources: "Modules/WatchOSDynamicFramework/Sources/**/*.swift",
    dependencies: [
        .target(name: "MultiPlatformTransitiveDynamicFramework", condition: .when([.watchos])),
        .external(name: "StructBuilder", condition: .when([.watchos])),
        .external(name: "ComposableArchitecture"),
    ]
)

let macOSStaticFramework: Target = .target(
    name: "MacOSStaticFramework",
    destinations: [.mac],
    product: .staticFramework,
    bundleId: "dev.tuist.App.MacOSStaticFramework",
    deploymentTargets: .multiplatform(macOS: "14.0.0"),
    sources: "Modules/MacOSStaticFramework/Sources/**/*.swift",
    resources: "Modules/MacOSStaticFramework/Resources/**",
    dependencies: [
        .target(name: "MultiPlatformTransitiveDynamicFramework", condition: .when([.macos])),
    ]
)

let macOSStaticFrameworkTests: Target = .target(
    name: "MacOSStaticFrameworkTests",
    destinations: [.mac],
    product: .unitTests,
    bundleId: "dev.tuist.App.MacOSStaticFrameworkTests",
    deploymentTargets: .multiplatform(macOS: "14.0.0"),
    sources: "Modules/MacOSStaticFrameworkTests/Sources/**/*.swift",
    dependencies: [
        .target(name: "MacOSStaticFramework", condition: .when([.macos])),
    ]
)

let multiPlatformTransitiveDynamicFramework: Target = .target(
    name: "MultiPlatformTransitiveDynamicFramework",
    destinations: [.iPhone, .iPad, .mac, .appleWatch],
    product: .framework,
    bundleId: "dev.tuist.App.MultiPlatformTransitiveDynamicFramework",
    deploymentTargets: .multiplatform(iOS: "14.0", macOS: "14.0.0", watchOS: "9.0"),
    sources: "Modules/MultiPlatformTransitiveDynamicFramework/Sources/**/*.swift"
)

let project = Project(
    name: "App",
    targets: [
        appTarget,
        iOSStaticFramework,
        watchOSDynamicFramework,
        macOSStaticFramework,
        macOSStaticFrameworkTests,
        multiPlatformTransitiveDynamicFramework,
    ]
)
