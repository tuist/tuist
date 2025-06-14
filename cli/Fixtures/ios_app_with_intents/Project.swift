import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: "Info.plist",
            sources: [
                "Sources/**",
                .glob("Intents/Public.intentdefinition", codeGen: .public),
                .glob("Intents/Private.intentdefinition", codeGen: .private),
                .glob("Intents/Project.intentdefinition", codeGen: .project),
                .glob("Intents/Disabled.intentdefinition", codeGen: .disabled),
            ]
        ),
    ]
)
