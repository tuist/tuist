import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(path: "LocalSwiftPackage"),
    ],
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["App/Sources/**"],
            resources: [],
            dependencies: [
                .package(product: "LocalSwiftPackage"),
            ]
        ),
    ]
)
