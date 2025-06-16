import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "Tuist",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: "Info.plist",
            sources: "App/**"
        ),
    ]
)
