import ProjectDescription

let project = Project(
    name: "Project",
    targets: [
        Target(
            name: "MyTestFramework",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.MyTestFramework",
            infoPlist: .default,
            sources: "MyTestFramework/**",
            dependencies: [
                .xctest,
            ]
        ),
        Target(
            name: "AppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: "Support/Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
                .target(name: "MyTestFramework"),
            ]
        ),
    ],
    multiplatformTargets: [
        Multiplatform.Target(
            name: "App",
            destinations: [.iPhone, .iPad, .mac],
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Support/App-Info.plist",
            sources: "App/**",
            dependencies: [
                .sdk(name: "CloudKit", type: .framework, status: .required),
                .sdk(name: "ARKit", type: .framework, status: .required),
                .sdk(name: "MobileCoreServices", type: .framework, status: .required),
            ]
        ),
        Multiplatform.Target(
            name: "MultiPlatformFramework",
            destinations: [.iPad, .iPhone, .mac, .appleTv],
            product: .framework,
            bundleId: "io.tuist.MacFramework",
            infoPlist: "Support/Framework-Info.plist",
            sources: "Framework/**",
            dependencies: [
                .sdk(name: "CloudKit", type: .framework, status: .optional),
                .sdk(name: "sqlite3", type: .library),
            ]
        ),
    ]
)
