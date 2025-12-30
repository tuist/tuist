import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone, .iPad, .macCatalyst],
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["App/Sources/**"],
            dependencies: [
                .target(name: "Framework"),
            ]
        ),
        .target(
            name: "Framework",
            destinations: [.iPhone, .iPad, .macCatalyst],
            product: .framework,
            bundleId: "dev.tuist.Framework",
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleShortVersionString": "1.0",
                ]
            ),
            sources: ["Framework/Sources/**"]
        ),
    ]
)
