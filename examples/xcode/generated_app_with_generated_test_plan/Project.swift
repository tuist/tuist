import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: .default,
            sources: ["Targets/App/Tests/**"],
            dependencies: [.target(name: "App")]
        ),
        .target(
            name: "AppSnapshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppSnapshotTests",
            infoPlist: .default,
            sources: ["Targets/App/SnapshotTests/**"],
            dependencies: [.target(name: "App")]
        ),
        .target(
            name: "DisabledTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.DisabledTests",
            infoPlist: .default,
            sources: ["Targets/App/DisabledTests/**"],
            dependencies: [.target(name: "App")]
        ),
    ],
    schemes: [
        .scheme(
            name: "App",
            buildAction: .buildAction(targets: ["App"]),
            testAction: .testPlans([
                .generated(
                    name: "UnitTests",
                    testTargets: [
                        .testableTarget(
                            target: "AppTests",
                            parallelization: .enabled,
                            selectedTests: ["AppTests/test_selected()"],
                            skippedTests: ["AppTests/test_skipped()"]
                        ),
                        .testableTarget(target: "DisabledTests", isSkipped: true),
                    ],
                    defaultOptions: .options(
                        arguments: .arguments(
                            environmentVariables: [
                                "FEATURE": .environmentVariable(value: "enabled", isEnabled: true),
                            ],
                            launchArguments: [
                                .launchArgument(name: "-feature", isEnabled: true),
                            ]
                        ),
                        codeCoverage: .specificTargets(["App"]),
                        expandVariableFromTarget: "App",
                        language: "en",
                        region: "US",
                        preferredScreenCaptureFormat: .screenshots,
                        testExecutionOrdering: .random,
                        parallelizationMode: .enabled,
                        testRepetitionMode: .retryOnFailure,
                        maximumTestRepetitions: 2,
                        repeatInNewRunnerProcess: true,
                        testTimeoutsEnabled: false,
                        defaultTestExecutionTimeAllowance: 60,
                        maximumTestExecutionTimeAllowance: 120,
                        userAttachmentLifetime: .keepAlways,
                        uiTestingScreenshotsLifetime: .keepNever,
                        areLocalizationScreenshotsEnabled: true,
                        diagnosticCollectionPolicy: .onFailure,
                        distributor: .testFlight,
                        locationScenario: TestPlanLocationScenario(identifier: "Berlin, Germany"),
                        addressSanitizer: .disabled,
                        threadSanitizerEnabled: false,
                        mainThreadCheckerEnabled: false,
                        performanceAntipatternCheckerEnabled: false,
                        undefinedBehaviorSanitizerEnabled: false,
                        zombieObjectsEnabled: false,
                        guardMallocEnabled: false,
                        mallocScribbleEnabled: false,
                        mallocGuardEdgesEnabled: false,
                        mallocStackLogging: nil,
                        checkedAllocations: .disabled,
                        runtimeIssueDetection: .enabled(.error),
                        mainThreadCheckerDetectionPolicy: .enabled(.error),
                        threadPerformanceCheckerRuntimeIssueDetection: .enabled(.error)
                    ),
                    options: [
                        "Configuration 1": .options(),
                        "Configuration 2": .options(
                            testExecutionOrdering: .alphabetical,
                            testTimeoutsEnabled: true
                        ),
                    ]
                ),
                .generated(
                    name: "SnapshotTests",
                    testTargets: [.testableTarget(target: "AppSnapshotTests")]
                ),
            ]),
            runAction: .runAction(configuration: .debug, executable: "App")
        ),
    ]
)
