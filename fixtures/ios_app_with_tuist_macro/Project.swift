import ProjectDescription

let project = Project(
    name: "ios_app_with_tuist_macro",
    targets: [
        .target(
            name: "ios_app_with_tuist_macro",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.ios-app-with-tuist-macro",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["ios_app_with_tuist_macro/Sources/**"],
            resources: ["ios_app_with_tuist_macro/Resources/**"],
            dependencies: [
				.project(target: "TuistMacro", path: "TuistMacro")
			]
        ),
        .target(
            name: "ios_app_with_tuist_macroTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.ios-app-with-tuist-macroTests",
            infoPlist: .default,
            sources: ["ios_app_with_tuist_macro/Tests/**"],
            resources: [],
            dependencies: [.target(name: "ios_app_with_tuist_macro")]
        ),
    ]
)
