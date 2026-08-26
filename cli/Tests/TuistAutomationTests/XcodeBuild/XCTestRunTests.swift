#if os(macOS)
    import Foundation
    import Testing

    @testable import TuistAutomation

    struct XCTestRunTests {
        // MARK: - Format v2 (TestConfigurations)

        @Test
        func decode_v2_parsesTestModules() throws {
            let plist = try makePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            ["BlueprintName": "AppTests"],
                            ["BlueprintName": "CoreTests"],
                        ],
                    ],
                ],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(xcTestRun.testModules == ["AppTests", "CoreTests"])
        }

        @Test
        func decode_v2_multipleConfigurations() throws {
            let plist = try makePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            ["BlueprintName": "UnitTests"],
                        ],
                    ],
                    [
                        "TestTargets": [
                            ["BlueprintName": "UITests"],
                        ],
                    ],
                ],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(xcTestRun.testModules == ["UnitTests", "UITests"])
        }

        // MARK: - Parallelization

        @Test
        func decode_v2_parsesParallelizableTestModules() throws {
            let plist = try makePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            ["BlueprintName": "ParallelTests", "ParallelizationEnabled": true],
                            ["BlueprintName": "SerialTests", "ParallelizationEnabled": false],
                            ["BlueprintName": "UnstatedTests"],
                        ],
                    ],
                ],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            // A target that does not state the key is not claimed to be parallel.
            #expect(xcTestRun.parallelizableTestModules == ["ParallelTests"])
        }

        @Test
        func decode_v2_parallelizableInAnyConfigurationCounts() throws {
            let plist = try makePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            ["BlueprintName": "AppTests", "ParallelizationEnabled": false],
                        ],
                    ],
                    [
                        "TestTargets": [
                            ["BlueprintName": "AppTests", "ParallelizationEnabled": true],
                        ],
                    ],
                ],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(xcTestRun.parallelizableTestModules == ["AppTests"])
        }

        @Test
        func decode_v1_parsesParallelizableTestModules() throws {
            let plist = try makePlist([
                "__xctestrun_metadata__": ["FormatVersion": 1],
                "ParallelTests": ["BlueprintName": "ParallelTests", "ParallelizationEnabled": true],
                "SerialTests": ["BlueprintName": "SerialTests"],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(xcTestRun.testModules.sorted() == ["ParallelTests", "SerialTests"])
            #expect(xcTestRun.parallelizableTestModules == ["ParallelTests"])
        }

        // MARK: - Skipped tests

        @Test
        func decode_v2_parsesSkippedTestSuiteIdentifiers() throws {
            let plist = try makePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            [
                                "BlueprintName": "AppUITests",
                                "SkipTestIdentifiers": ["OnboardingFlowTests", "SettingsFlowTests/testExample"],
                            ],
                        ],
                    ],
                ],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            // A skip naming a whole suite takes it out of the run. A skip naming a single test
            // doesn't, because the suite holding it may still have tests left to run.
            #expect(xcTestRun.skippedTestSuiteIdentifiers() == ["AppUITests/OnboardingFlowTests"])
        }

        @Test
        func decode_v2_selectedSuitesAreReportedWholeAlongsideTheSkips() throws {
            let plist = try makePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            [
                                "BlueprintName": "AppUITests",
                                "OnlyTestIdentifiers": ["OnboardingFlowTests", "CheckoutFlowTests/testExample()"],
                                "SkipTestIdentifiers": ["OnboardingFlowTests"],
                            ],
                        ],
                    ],
                ],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            // The selection is reported in full even where the skips cancel it out. It is what tells
            // the consumer which modules the products restrict at all, and narrowing it here would
            // make a module whose every selected suite is skipped look unrestricted.
            #expect(
                xcTestRun.selectedTestSuiteIdentifiers() == [
                    "AppUITests/CheckoutFlowTests",
                    "AppUITests/OnboardingFlowTests",
                ]
            )
            #expect(xcTestRun.skippedTestSuiteIdentifiers() == ["AppUITests/OnboardingFlowTests"])
        }

        @Test
        func decode_v2_parsesNestedSuiteSkips() throws {
            let plist = try makePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            [
                                "BlueprintName": "AppUITests",
                                "SkipTestIdentifiers": ["OnboardingFlowTests/NestedFlowTests"],
                            ],
                        ],
                    ],
                ],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            // A nested Swift Testing suite is skipped by its path, and a suite is named by its
            // innermost component, matching how a run reports it.
            #expect(xcTestRun.skippedTestSuiteIdentifiers() == ["AppUITests/NestedFlowTests"])
        }

        @Test
        func decode_v2_ignoresSkipsNamingASingleTest() throws {
            let plist = try makePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            [
                                "BlueprintName": "AppUITests",
                                "SkipTestIdentifiers": [
                                    "OnboardingFlowTests/testExample",
                                    "CheckoutFlowTests/testExample()",
                                    "SettingsFlowTests/NestedFlowTests/testExample()",
                                ],
                            ],
                        ],
                    ],
                ],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            // Skips naming a single test leave their suite with tests that may still run. A trailing
            // "()" and a lowercase first character both mark a function rather than a type.
            #expect(xcTestRun.skippedTestSuiteIdentifiers().isEmpty)
        }

        @Test
        func decode_v2_noSkippedIdentifiers() throws {
            let plist = try makePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            ["BlueprintName": "AppUITests"],
                        ],
                    ],
                ],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(xcTestRun.skippedTestSuiteIdentifiers().isEmpty)
        }

        // MARK: - Format v1 (Legacy top-level keys)

        @Test
        func decode_v1_parsesTestModules() throws {
            let plist = try makePlist([
                "__xctestrun_metadata__": ["FormatVersion": 1],
                "AppTests": ["BlueprintName": "AppTests", "TestHostPath": "/path"],
                "CoreTests": ["BlueprintName": "CoreTests", "TestHostPath": "/path"],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(Set(xcTestRun.testModules) == Set(["AppTests", "CoreTests"]))
        }

        @Test
        func decode_v1_skipsMetadataKey() throws {
            let plist = try makePlist([
                "__xctestrun_metadata__": ["FormatVersion": 1, "ContainerInfo": ["SchemeName": "App"]],
                "AppTests": ["BlueprintName": "AppTests"],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(xcTestRun.testModules == ["AppTests"])
        }

        @Test
        func decode_v1_emptyTargets() throws {
            let plist = try makePlist([
                "__xctestrun_metadata__": ["FormatVersion": 1],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(xcTestRun.testModules.isEmpty)
        }

        // MARK: - Helpers

        private func makePlist(_ dict: [String: Any]) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        }
    }
#endif
