import ProjectDescription

let project = Project(
    name: "App",
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
            buildableFolders: [
                "App/Sources",
                "App/Resources",
            ],
            dependencies: [
                .target(name: "Framework"),
            ],
            settings: .settings(base: [
                "SWIFT_OBJC_BRIDGING_HEADER": "$SRCROOT/App/Sources/include/App.h",
            ])
        ),
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.Framework",
            buildableFolders: [
                "Framework/Resources",
                .folder("Framework/Sources", exceptions: .exceptions([
                    .exception(publicHeaders: ["Framework.h", "include/bar.h", "include/baz.h"]),
                ])),
            ]
        ),
    ]
)
