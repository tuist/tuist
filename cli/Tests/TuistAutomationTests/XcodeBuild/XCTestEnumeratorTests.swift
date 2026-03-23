#if os(macOS)
    import Command
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Mockable
    import Path
    import Testing

    @testable import TuistAutomation

    struct XCTestEnumeratorTests {
        let subject: XCTestEnumerator
        let commandRunner: MockCommandRunning

        init() {
            commandRunner = MockCommandRunning()
            subject = XCTestEnumerator(commandRunner: commandRunner)
        }

        private func givenCommandOutput(_ output: String) {
            given(commandRunner)
                .run(arguments: .any, environment: .any, workingDirectory: .any)
                .willProduce { _, _, _ in
                    AsyncThrowingStream { continuation in
                        continuation.yield(CommandEvent.standardOutput(Array(output.utf8)))
                        continuation.finish()
                    }
                }
        }

        private func givenCommandError(_ message: String) {
            given(commandRunner)
                .run(arguments: .any, environment: .any, workingDirectory: .any)
                .willProduce { _, _, _ in
                    AsyncThrowingStream { continuation in
                        continuation.finish(throwing: NSError(
                            domain: "test",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: message]
                        ))
                    }
                }
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_parsesMultipleTargetsAndSuites() async throws {
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
            givenCommandOutput(jsonOutput)

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: nil
            )

            let appTests = result.first { $0.blueprintName == "AppTests" }
            #expect(appTests?.onlyTestIdentifiers == ["LoginTests", "SignupTests"])
            let coreTests = result.first { $0.blueprintName == "CoreTests" }
            #expect(coreTests?.onlyTestIdentifiers == ["NetworkTests"])
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_withDestination() async throws {
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
            givenCommandOutput(jsonOutput)

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: "platform=iOS Simulator,name=iPhone 16"
            )

            let uiTests = result.first { $0.blueprintName == "UITests" }
            #expect(uiTests?.onlyTestIdentifiers == ["SnapshotTests"])
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_withEmptySubtests() async throws {
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
            givenCommandOutput(jsonOutput)

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: nil
            )

            let emptyTarget = result.first { $0.blueprintName == "EmptyTarget" }
            #expect(emptyTarget?.onlyTestIdentifiers == nil)
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_throwsEnumerationFailedWhenCommandFails() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            givenCommandError("something went wrong")

            await #expect(throws: XCTestEnumeratorError.self) {
                try await subject.enumerateTests(
                    testProductsPath: testProductsPath,
                    destination: nil
                )
            }
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_throwsInvalidOutputForMalformedJSON() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            givenCommandOutput("not json")

            await #expect(throws: XCTestEnumeratorError.self) {
                try await subject.enumerateTests(
                    testProductsPath: testProductsPath,
                    destination: nil
                )
            }
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_withMultipleValues() async throws {
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
            givenCommandOutput(jsonOutput)

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: nil
            )

            let targetA = result.first { $0.blueprintName == "TargetA" }
            #expect(targetA?.onlyTestIdentifiers == ["SuiteA"])
            let targetB = result.first { $0.blueprintName == "TargetB" }
            #expect(targetB?.onlyTestIdentifiers == ["SuiteB"])
        }
    }
#endif
