import ProjectDescription

let project = Project(
    name: "Library",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "Library",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.Library",
            sources: ["Sources/**"],
            dependencies: [
                .xcframework(path: "GoogleMapsCore.xcframework"),
                .xcframework(path: "GoogleMaps.xcframework"),
                .xcframework(path: "GoogleMapsBase.xcframework"),
                .sdk(name: "c++", type: .library),
            ]
        ),
    ]
)
