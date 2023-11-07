import ProjectDescription

let project = Project(
    name: "AppWithSpace",
    targets: [
        Target(
            name: "AppWithSpace",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app-with-space",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            scripts: [
                .pre(path: "script.sh", name: "Run script"),
            ]
        ),
    ]
)
