#if os(macOS)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Path
    import Testing
    import TuistSupport

    @testable import TuistAutomation
    @testable import TuistTesting

    struct XCTestEnumeratorTests {
        let subject: XCTestEnumerator
        let system: MockSystem

        init() {
            system = MockSystem()
            System._shared.mutate { $0 = system }
            subject = XCTestEnumerator()
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_parsesMultipleTargetsAndSuites() async throws {
            // Given
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            let jsonOutput = """
            {
                "values": [
                    {
                        "subtests": [
                            {
                                "name": "AppTests",
                                "subtests": [
                                    { "name": "LoginTests" },
                                    { "name": "SignupTests" }
                                ]
                            },
                            {
                                "name": "CoreTests",
                                "subtests": [
                                    { "name": "NetworkTests" }
                                ]
                            }
                        ]
                    }
                ]
            }
            """
            system.succeedCommand(
                [
                    "xcodebuild", "test-without-building",
                    "-enumerate-tests",
                    "-testProductsPath", testProductsPath.pathString,
                    "-scheme", "App",
                ],
                output: jsonOutput
            )

            // When
            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                scheme: "App",
                destination: nil
            )

            // Then
            #expect(result["AppTests"] == ["LoginTests", "SignupTests"])
            #expect(result["CoreTests"] == ["NetworkTests"])
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_withDestination() async throws {
            // Given
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            let jsonOutput = """
            {
                "values": [
                    {
                        "subtests": [
                            {
                                "name": "UITests",
                                "subtests": [
                                    { "name": "SnapshotTests" }
                                ]
                            }
                        ]
                    }
                ]
            }
            """
            system.succeedCommand(
                [
                    "xcodebuild", "test-without-building",
                    "-enumerate-tests",
                    "-testProductsPath", testProductsPath.pathString,
                    "-scheme", "App",
                    "-destination", "platform=iOS Simulator,name=iPhone 16",
                ],
                output: jsonOutput
            )

            // When
            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                scheme: "App",
                destination: "platform=iOS Simulator,name=iPhone 16"
            )

            // Then
            #expect(result["UITests"] == ["SnapshotTests"])
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_withEmptySubtests() async throws {
            // Given
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            let jsonOutput = """
            {
                "values": [
                    {
                        "subtests": [
                            {
                                "name": "EmptyTarget"
                            }
                        ]
                    }
                ]
            }
            """
            system.succeedCommand(
                [
                    "xcodebuild", "test-without-building",
                    "-enumerate-tests",
                    "-testProductsPath", testProductsPath.pathString,
                    "-scheme", "App",
                ],
                output: jsonOutput
            )

            // When
            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                scheme: "App",
                destination: nil
            )

            // Then
            #expect(result["EmptyTarget"] == [])
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_throwsEnumerationFailedWhenCommandFails() async throws {
            // Given
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            system.errorCommand(
                [
                    "xcodebuild", "test-without-building",
                    "-enumerate-tests",
                    "-testProductsPath", testProductsPath.pathString,
                    "-scheme", "App",
                ],
                error: "something went wrong"
            )

            // When / Then
            await #expect(throws: XCTestEnumeratorError.self) {
                try await subject.enumerateTests(
                    testProductsPath: testProductsPath,
                    scheme: "App",
                    destination: nil
                )
            }
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_throwsInvalidOutputForMalformedJSON() async throws {
            // Given
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            system.succeedCommand(
                [
                    "xcodebuild", "test-without-building",
                    "-enumerate-tests",
                    "-testProductsPath", testProductsPath.pathString,
                    "-scheme", "App",
                ],
                output: "not json"
            )

            // When / Then
            await #expect(throws: XCTestEnumeratorError.self) {
                try await subject.enumerateTests(
                    testProductsPath: testProductsPath,
                    scheme: "App",
                    destination: nil
                )
            }
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_withMultipleValues() async throws {
            // Given
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            let jsonOutput = """
            {
                "values": [
                    {
                        "subtests": [
                            {
                                "name": "TargetA",
                                "subtests": [{ "name": "SuiteA" }]
                            }
                        ]
                    },
                    {
                        "subtests": [
                            {
                                "name": "TargetB",
                                "subtests": [{ "name": "SuiteB" }]
                            }
                        ]
                    }
                ]
            }
            """
            system.succeedCommand(
                [
                    "xcodebuild", "test-without-building",
                    "-enumerate-tests",
                    "-testProductsPath", testProductsPath.pathString,
                    "-scheme", "App",
                ],
                output: jsonOutput
            )

            // When
            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                scheme: "App",
                destination: nil
            )

            // Then
            #expect(result["TargetA"] == ["SuiteA"])
            #expect(result["TargetB"] == ["SuiteB"])
        }
    }
#endif
