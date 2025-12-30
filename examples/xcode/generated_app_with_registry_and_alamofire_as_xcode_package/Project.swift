import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(id: "Alamofire.Alamofire", exact: "5.10.2"),
    ],
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
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
                .package(product: "Alamofire"),
            ]
        ),
    ]
)
