import ProjectDescription

let project = Project(
    name: "TuistShare",
    targets: [
        .target(
            name: "TuistShare",
            destinations: .macOS,
            product: .app,
            bundleId: "io.tuist.TuistShare",
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleURLTypes": .array(
                        [
                            Plist.Value.dictionary(
                                [
                                    "CFBundleTypeRole": "Viewer",
                                    "CFBundleURLName": "io.tuist.TuistShare",
                                    "CFBundleURLSchemes": .array(["tuist-share"])
                                ]
                            )
                        ]
                    )
                ]
            ),
            sources: ["TuistShare/Sources/**"],
            resources: ["TuistShare/Resources/**"],
            dependencies: [
                .external(name: "Path"),
                .external(name: "TuistSupport"),
                .external(name: "TuistCore"),
                .external(name: "TuistServer"),
            ]
        ),
        .target(
            name: "TuistShareTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "io.tuist.TuistShareTests",
            infoPlist: .default,
            sources: ["TuistShare/Tests/**"],
            resources: [],
            dependencies: [.target(name: "TuistShare")]
        ),
    ]
)
