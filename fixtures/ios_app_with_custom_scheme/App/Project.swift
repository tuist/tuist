import ProjectDescription

let debugAction: ExecutionAction = .executionAction(scriptText: "echo Debug", target: "App")
let debugScheme: Scheme = .scheme(
    name: "App-Debug",
    shared: true,
    buildAction: .buildAction(
        targets: ["App"],
        preActions: [debugAction],
        runPostActionsOnFailure: true
    ),
    testAction: .targets(
        [
            .testableTarget(
                target: "AppTests",
                simulatedLocation: .rioDeJaneiro
            ),
        ]
    ),
    runAction: .runAction(
        customLLDBInitFile: "../Scripts/lldb/_lldbinit",
        executable: "App",
        options: .options(
            storeKitConfigurationPath: "Config/ProjectStoreKitConfig.storekit",
            simulatedLocation: .johannesburg,
            enableGPUFrameCaptureMode: .metal
        ),
        diagnosticsOptions: .options(mainThreadCheckerEnabled: true)
    )
)

let releaseAction: ExecutionAction = .executionAction(scriptText: "echo Release", target: "App")
let releaseScheme: Scheme = .scheme(
    name: "App-Release",
    shared: true,
    buildAction: .buildAction(targets: ["App"], preActions: [releaseAction]),
    testAction: .targets(
        [
            .testableTarget(
                target: "AppTests",
                simulatedLocation: .custom(gpxFile: "Resources/Grand Canyon.gpx")
            ),
        ]
    ),
    runAction: .runAction(
        executable: "App",
        options: .options(
            simulatedLocation: .custom(gpxFile: "Resources/Grand Canyon.gpx"),
            enableGPUFrameCaptureMode: .disabled
        ),
        diagnosticsOptions: .options(mainThreadCheckerEnabled: true)
    )
)

let userScheme: Scheme = .scheme(
    name: "App-Local",
    shared: false,
    buildAction: .buildAction(targets: ["App"], preActions: [debugAction]),
    testAction: TestAction.targets(["AppTests"]),
    runAction: .runAction(executable: "App")
)

let project = Project(
    name: "MainApp",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Config/App-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "Framework1", path: "../Frameworks/Framework1"),
                .project(target: "Framework2", path: "../Frameworks/Framework2"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: "Config/AppTests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ],
    schemes: [debugScheme, releaseScheme, userScheme]
)
