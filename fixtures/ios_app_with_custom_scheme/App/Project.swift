import ProjectDescription

let debugAction = ExecutionAction(scriptText: "echo Debug", target: "App")
let debugScheme = .scheme(
    name: "App-Debug",
    shared: true,
    buildAction: .buildAction(
        targets: ["App"],
        preActions: [debugAction],
        runPostActionsOnFailure: true
    ),
    testAction: TestAction.targets(["AppTests"]),
    runAction: .runAction(
        customLLDBInitFile: "../Scripts/lldb/_lldbinit",
        executable: "App",
        options: .options(
            storeKitConfigurationPath: "Config/ProjectStoreKitConfig.storekit",
            simulatedLocation: .johannesburg,
            enableGPUFrameCaptureMode: .metal
        ),
        diagnosticsOptions: [.mainThreadChecker]
    )
)

let releaseAction = ExecutionAction(scriptText: "echo Release", target: "App")
let releaseScheme = .scheme(
    name: "App-Release",
    shared: true,
    buildAction: .buildAction(targets: ["App"], preActions: [releaseAction]),
    testAction: TestAction.targets(["AppTests"]),
    runAction: .runAction(
        executable: "App",
        options: .options(
            simulatedLocation: .custom(gpxFile: "Resources/Grand Canyon.gpx"),
            enableGPUFrameCaptureMode: .disabled
        ),
        diagnosticsOptions: [.mainThreadChecker]
    )
)

let userScheme = .scheme(
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
