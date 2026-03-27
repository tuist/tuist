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
        func enumerateTests_parsesMultipleTargetsAndClasses() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            let textOutput = """
            Plan MyScheme
            \tTarget AppTests
            \t\tClass LoginTests
            \t\t\tTest testLogin()
            \t\tClass SignupTests
            \t\t\tTest testSignup()
            \tTarget CoreTests
            \t\tClass NetworkTests
            \t\t\tTest testFetch()
            """
            givenCommandOutput(textOutput)

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
            let textOutput = """
            Plan MyScheme
            \tTarget UITests
            \t\tClass SnapshotTests
            \t\t\tTest testSnapshot()
            """
            givenCommandOutput(textOutput)

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: "platform=iOS Simulator,name=iPhone 16"
            )

            let uiTests = result.first { $0.blueprintName == "UITests" }
            #expect(uiTests?.onlyTestIdentifiers == ["SnapshotTests"])
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_targetWithNoClasses() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            let textOutput = """
            Plan MyScheme
            \tTarget EmptyTarget
            """
            givenCommandOutput(textOutput)

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: nil
            )

            #expect(result.isEmpty)
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
        func enumerateTests_returnsEmptyForUnrecognizedOutput() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            givenCommandOutput("some random text")

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: nil
            )

            #expect(result.isEmpty)
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_multipleTargets() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            let textOutput = """
            Plan MyScheme
            \tTarget TargetA
            \t\tClass SuiteA
            \t\t\tTest testA()
            \tTarget TargetB
            \t\tClass SuiteB
            \t\t\tTest testB()
            """
            givenCommandOutput(textOutput)

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
