import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "Tuist",
    targets: [
        Target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: "Info.plist",
            sources: "App/**"
        ),
    ]
)
