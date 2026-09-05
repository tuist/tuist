import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
import XcodeProj

struct TestPlanDescriptorTests {
    @Test func encode_produces_valid_xctestplan_json() throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "AppTests")
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [
                TestPlanDescriptor.TestTarget(
                    pbxTarget: pbxTarget,
                    containerPath: "container:App.xcodeproj",
                    isEnabled: true,
                    parallelization: .swiftTestingOnly
                ),
            ]
        )

        // When
        let data = try descriptor.encode()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Then
        #expect(json?["version"] as? Int == 1)
        let testTargets = try #require(json?["testTargets"] as? [[String: Any]])
        #expect(testTargets.count == 1)
        let target = try #require(testTargets.first?["target"] as? [String: String])
        #expect(target["containerPath"] == "container:App.xcodeproj")
        #expect(target["name"] == "AppTests")
        #expect(target["identifier"] != nil)
        #expect(testTargets.first?["enabled"] == nil) // enabled omitted when true
        #expect(testTargets.first?["parallelizable"] == nil) // swiftTestingOnly omits the field
    }

    @Test func encode_configuration_id_is_deterministic_per_name() throws {
        // Given
        let target = PBXNativeTarget(name: "AppTests")
        func descriptor(at pathString: String, configurationName: String) throws -> TestPlanDescriptor {
            TestPlanDescriptor(
                path: try AbsolutePath(validating: pathString),
                testTargets: [
                    .init(
                        pbxTarget: target,
                        containerPath: "container:App.xcodeproj",
                        isEnabled: true,
                        parallelization: .swiftTestingOnly
                    ),
                ],
                options: [configurationName: TestPlanDescriptor.Options()]
            )
        }

        // When
        let firstRun = try JSONSerialization.jsonObject(
            with: try descriptor(at: "/tmp/A.xctestplan", configurationName: "Configuration 1").encode()
        )
        let secondRun = try JSONSerialization.jsonObject(
            with: try descriptor(at: "/tmp/B.xctestplan", configurationName: "Configuration 1").encode()
        )
        let differentName = try JSONSerialization.jsonObject(
            with: try descriptor(at: "/tmp/A.xctestplan", configurationName: "Configuration 2").encode()
        )

        // Then
        func configurationID(_ object: Any) throws -> String {
            let dict = try #require(object as? [String: Any])
            let configurations = try #require(dict["configurations"] as? [[String: Any]])
            return try #require(configurations.first?["id"] as? String)
        }

        #expect(try configurationID(firstRun) == configurationID(secondRun))
        #expect(try configurationID(firstRun) != configurationID(differentName))
    }

    @Test func encode_marks_disabled_targets() throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "AppTests")
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [
                TestPlanDescriptor.TestTarget(
                    pbxTarget: pbxTarget,
                    containerPath: "container:App.xcodeproj",
                    isEnabled: false,
                    parallelization: .swiftTestingOnly
                ),
            ]
        )

        // When
        let data = try descriptor.encode()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Then
        let testTargets = try #require(json?["testTargets"] as? [[String: Any]])
        #expect(testTargets.first?["enabled"] as? Bool == false)
    }

    @Test func encode_parallelization_writes_parallelizable_field() throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "AppTests")
        func descriptor(parallelization: TestableTarget.Parallelization) throws -> TestPlanDescriptor {
            TestPlanDescriptor(
                path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
                testTargets: [
                    .init(
                        pbxTarget: pbxTarget,
                        containerPath: "container:App.xcodeproj",
                        isEnabled: true,
                        parallelization: parallelization
                    ),
                ]
            )
        }

        func parallelizable(_ plan: TestPlanDescriptor) throws -> Any? {
            let data = try plan.encode()
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let testTargets = try #require(json?["testTargets"] as? [[String: Any]])
            return testTargets.first?["parallelizable"]
        }

        // Then
        #expect(try parallelizable(descriptor(parallelization: .all)) as? Bool == true)
        #expect(try parallelizable(descriptor(parallelization: .none)) as? Bool == false)
        #expect(try parallelizable(descriptor(parallelization: .swiftTestingOnly)) == nil)
    }

    @Test func encode_writes_generated_test_plan_options() throws {
        // Given
        let app = PBXNativeTarget(name: "App")
        let tests = PBXNativeTarget(name: "AppTests")
        let appTarget = TestPlanDescriptor.TestTarget(
            pbxTarget: app,
            containerPath: "container:App.xcodeproj",
            isEnabled: true,
            parallelization: .none
        )
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [
                .init(
                    pbxTarget: tests,
                    containerPath: "container:App.xcodeproj",
                    isEnabled: true,
                    parallelization: .all,
                    skippedTests: ["AppTests/testExample()"],
                    selectedTests: ["AppTests/testSelectedExample()"]
                ),
            ],
            defaultOptions: TestPlanDescriptor.Options(
                values: TestPlanOptions(
                    arguments: Arguments(
                        environmentVariables: ["FEATURE": EnvironmentVariable(value: "enabled", isEnabled: true)],
                        launchArguments: [LaunchArgument(name: "-feature", isEnabled: true)]
                    ),
                    codeCoverage: .specificTargets([]),
                    language: "en",
                    region: "US",
                    preferredScreenCaptureFormat: .screenRecording,
                    testExecutionOrdering: "random",
                    testRepetitionMode: "untilFailure",
                    maximumTestRepetitions: 5,
                    repeatInNewRunnerProcess: true,
                    testTimeoutsEnabled: true,
                    defaultTestExecutionTimeAllowance: 30,
                    maximumTestExecutionTimeAllowance: 60,
                    userAttachmentLifetime: "keepAlways",
                    uiTestingScreenshotsLifetime: "keepNever",
                    areLocalizationScreenshotsEnabled: true,
                    diagnosticCollectionPolicy: "OnFailure",
                    distributor: "com.apple.TestFlight",
                    locationScenarioIdentifier: "Berlin, Germany",
                    locationScenarioReferenceType: "built-in",
                    testInteropMode: "complete",
                    applicationCrashDetectionSeverity: "fatalFailure",
                    addressSanitizer: .enabled(detectStackUseAfterReturn: true),
                    threadSanitizerEnabled: true,
                    mainThreadCheckerEnabled: true,
                    performanceAntipatternCheckerEnabled: true,
                    undefinedBehaviorSanitizerEnabled: true,
                    zombieObjectsEnabled: true,
                    guardMallocEnabled: true,
                    mallocScribbleEnabled: true,
                    mallocGuardEdgesEnabled: true,
                    mallocStackLogging: "allAllocations",
                    checkedAllocations: .always,
                    runtimeIssueDetection: .enabled("error"),
                    mainThreadCheckerDetectionPolicy: .enabled("warning"),
                    threadPerformanceCheckerRuntimeIssueDetection: .enabled("error"),
                    memoryTaggingAddressSanitizerEnabled: true
                ),
                codeCoverageTargets: [appTarget],
                expandVariableFromTarget: appTarget
            )
        )

        // When
        let json = try JSONSerialization.jsonObject(with: descriptor.encode()) as? [String: Any]

        // Then
        let configurations = try #require(json?["configurations"] as? [[String: Any]])
        let options = try #require(json?["defaultOptions"] as? [String: Any])
        let coverage = try #require(options["codeCoverage"] as? [String: Any])
        let coverageTargets = try #require(coverage["targets"] as? [[String: Any]])
        #expect(coverageTargets.first?["name"] as? String == "App")
        #expect(options["language"] as? String == "en")
        #expect(options["region"] as? String == "US")
        #expect(options["preferredScreenCaptureFormat"] as? String == "screenRecording")
        #expect((options["addressSanitizer"] as? [String: Any])?["enabled"] as? Bool == true)
        #expect((options["addressSanitizer"] as? [String: Any])?["detectStackUseAfterReturn"] as? Bool == true)
        #expect(options["threadSanitizerEnabled"] as? Bool == true)
        #expect(options["mainThreadCheckerEnabled"] as? Bool == true)
        #expect(options["performanceAntipatternCheckerEnabled"] as? Bool == true)
        #expect(options["undefinedBehaviorSanitizerEnabled"] as? Bool == true)
        #expect(options["nsZombieEnabled"] as? Bool == true)
        #expect(options["guardMallocEnabled"] as? Bool == true)
        #expect(options["mallocScribbleEnabled"] as? Bool == true)
        #expect(options["mallocGuardEdgesEnabled"] as? Bool == true)
        #expect((options["mallocStackLoggingOptions"] as? [String: Any])?["loggingType"] as? String == "allAllocations")
        #expect((options["checkedAllocations"] as? [String: Any])?["enabled"] as? Bool == true)
        #expect((options["checkedAllocations"] as? [String: Any])?["requiresHardwareAcceleration"] as? Bool == false)
        #expect((options["runtimeIssueDetection"] as? [String: Any])?["severity"] as? String == "error")
        #expect((options["mainThreadCheckerDetectionPolicy"] as? [String: Any])?["severity"] as? String == "warning")
        #expect((options["threadPerformanceCheckerRuntimeIssueDetection"] as? [String: Any])?["severity"] as? String == "error")
        #expect(options["testExecutionOrdering"] as? String == "random")
        #expect(options["testRepetitionMode"] as? String == "untilFailure")
        #expect(options["maximumTestRepetitions"] as? Int == 5)
        #expect(options["repeatInNewRunnerProcess"] as? Bool == true)
        #expect(options["testTimeoutsEnabled"] as? Bool == true)
        #expect(options["defaultTestExecutionTimeAllowance"] as? Int == 30)
        #expect(options["maximumTestExecutionTimeAllowance"] as? Int == 60)
        #expect(options["userAttachmentLifetime"] as? String == "keepAlways")
        #expect(options["uiTestingScreenshotsLifetime"] as? String == "keepNever")
        #expect(options["areLocalizationScreenshotsEnabled"] as? Bool == true)
        #expect(options["diagnosticCollectionPolicy"] as? String == "OnFailure")
        #expect(options["distributor"] as? String == "com.apple.TestFlight")
        #expect((options["locationScenario"] as? [String: Any])?["identifier"] as? String == "Berlin, Germany")
        #expect((options["locationScenario"] as? [String: Any])?["referenceType"] as? String == "built-in")
        #expect(options["testInteropMode"] as? String == "complete")
        #expect(options["applicationCrashDetectionSeverity"] as? String == "fatalFailure")
        #expect(options["memoryTaggingAddressSanitizerEnabled"] as? Bool == true)
        let arguments = try #require(options["commandLineArgumentEntries"] as? [[String: Any]])
        let argument = try #require(arguments.first)
        #expect(argument["argument"] as? String == "-feature")
        #expect(argument["enabled"] as? Bool == true)
        let environmentVariables = try #require(options["environmentVariableEntries"] as? [[String: Any]])
        let environmentVariable = try #require(environmentVariables.first)
        #expect(environmentVariable["key"] as? String == "FEATURE")
        #expect(environmentVariable["value"] as? String == "enabled")
        #expect(environmentVariable["enabled"] as? Bool == true)
        let testTargets = try #require(json?["testTargets"] as? [[String: Any]])
        #expect(testTargets.first?["skippedTests"] as? [String] == ["AppTests/testExample()"])
        #expect(testTargets.first?["selectedTests"] as? [String] == ["AppTests/testSelectedExample()"])
    }

    @Test func encode_writes_default_options_separately() throws {
        // Given
        let testTarget = PBXNativeTarget(name: "AppTests")
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [
                .init(
                    pbxTarget: testTarget,
                    containerPath: "container:App.xcodeproj",
                    isEnabled: true,
                    parallelization: .none
                ),
            ],
            defaultOptions: .init(
                values: TestPlanOptions(
                    codeCoverage: .allTargets,
                    testExecutionOrdering: "random",
                    mainThreadCheckerEnabled: false
                )
            )
        )

        // When
        let json = try JSONSerialization.jsonObject(with: descriptor.encode()) as? [String: Any]

        // Then
        let configurations = try #require(json?["configurations"] as? [[String: Any]])
        let options = try #require(json?["defaultOptions"] as? [String: Any])
        let configurationOptions = try #require(configurations.first?["options"] as? [String: Any])
        #expect(configurationOptions.isEmpty)
        #expect(Set(options.keys) == ["codeCoverage", "mainThreadCheckerEnabled", "testExecutionOrdering"])
        #expect(options["codeCoverage"] as? Bool == true)
        #expect(options["mainThreadCheckerEnabled"] as? Bool == false)
        #expect(options["testExecutionOrdering"] as? String == "random")
    }

    @Test func encode_writes_disabled_nested_options() throws {
        // Given
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [
                .init(
                    pbxTarget: PBXNativeTarget(name: "AppTests"),
                    containerPath: "container:App.xcodeproj",
                    isEnabled: true,
                    parallelization: .none
                ),
            ],
            defaultOptions: .init(
                values: TestPlanOptions(
                    codeCoverage: .disabled,
                    addressSanitizer: .disabled,
                    mallocStackLogging: "liveAllocations",
                    checkedAllocations: .disabled,
                    runtimeIssueDetection: .disabled,
                    mainThreadCheckerDetectionPolicy: .disabled,
                    threadPerformanceCheckerRuntimeIssueDetection: .disabled
                )
            )
        )

        // When
        let json = try JSONSerialization.jsonObject(with: descriptor.encode()) as? [String: Any]

        // Then
        let options = try #require(json?["defaultOptions"] as? [String: Any])
        #expect(options["codeCoverage"] as? Bool == false)
        #expect((options["addressSanitizer"] as? [String: Any])?["enabled"] as? Bool == false)
        #expect((options["mallocStackLoggingOptions"] as? [String: Any])?["loggingType"] as? String == "liveAllocations")
        #expect((options["checkedAllocations"] as? [String: Any])?["enabled"] as? Bool == false)
        #expect((options["runtimeIssueDetection"] as? [String: Any])?["enabled"] as? Bool == false)
        #expect((options["mainThreadCheckerDetectionPolicy"] as? [String: Any])?["enabled"] as? Bool == false)
        #expect(
            (options["threadPerformanceCheckerRuntimeIssueDetection"] as? [String: Any])?["enabled"] as? Bool == false
        )
    }

    @Test func encode_writes_hardware_accelerated_checked_allocations() throws {
        // Given
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [
                .init(
                    pbxTarget: PBXNativeTarget(name: "AppTests"),
                    containerPath: "container:App.xcodeproj",
                    isEnabled: true,
                    parallelization: .none
                ),
            ],
            defaultOptions: .init(values: TestPlanOptions(checkedAllocations: .mteOnly))
        )

        // When
        let json = try JSONSerialization.jsonObject(with: descriptor.encode()) as? [String: Any]

        // Then
        let options = try #require(json?["defaultOptions"] as? [String: Any])
        let checkedAllocations = try #require(options["checkedAllocations"] as? [String: Any])
        #expect(checkedAllocations["enabled"] as? Bool == true)
        #expect(checkedAllocations["requiresHardwareAcceleration"] as? Bool == true)
    }

    @Test func encode_preserves_explicit_nested_options_without_their_enablement_flags() throws {
        // Given
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [
                TestPlanDescriptor.TestTarget(
                    pbxTarget: PBXNativeTarget(name: "AppTests"),
                    containerPath: "container:App.xcodeproj",
                    isEnabled: true,
                    parallelization: .none
                ),
            ],
            defaultOptions: TestPlanDescriptor.Options(
                values: TestPlanOptions(
                    addressSanitizer: .enabled(detectStackUseAfterReturn: false),
                    checkedAllocations: .always
                )
            )
        )

        // When
        let json = try JSONSerialization.jsonObject(with: descriptor.encode()) as? [String: Any]

        // Then
        let options = try #require(json?["defaultOptions"] as? [String: Any])
        #expect((options["addressSanitizer"] as? [String: Any])?["detectStackUseAfterReturn"] as? Bool == false)
        #expect((options["checkedAllocations"] as? [String: Any])?["requiresHardwareAcceleration"] as? Bool == false)
    }
}
