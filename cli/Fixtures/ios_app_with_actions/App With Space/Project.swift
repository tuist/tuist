import ProjectDescription

let project = Project(
    name: "AppWithSpace",
    targets: [
        .target(
            name: "AppWithSpace",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app-with-space",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            scripts: [
                .pre(path: "script.sh", name: "Run script"),
            ]
        ),
    ]
)
