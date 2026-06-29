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

        /// Builds a hierarchical `-test-enumeration-format json` document for the given `target -> [class]` map.
        private func enumerationJSON(_ targets: [(String, [String])]) -> String {
            let targetNodes = targets.map { name, classes in
                let classNodes = classes.map { className in
                    """
                    {"kind":"class","name":"\(className)","children":[{"kind":"test","name":"t()"}]}
                    """
                }.joined(separator: ",")
                return #"{"kind":"target","name":"\#(name)","children":[\#(classNodes)]}"#
            }.joined(separator: ",")
            return #"{"errors":[],"values":[{"kind":"plan","name":"P","children":[\#(targetNodes)]}]}"#
        }

        /// Sets up the command runner mock to write `json` to the `-test-enumeration-output-path` the subject
        /// passes, mirroring how `xcodebuild` writes the enumeration file. Optionally captures the arguments.
        private func givenEnumeration(json: String, capturing box: ArgumentsBox? = nil) {
            given(commandRunner)
                .run(arguments: .any, environment: .any, workingDirectory: .any)
                .willProduce { arguments, _, _ in
                    box?.value = arguments
                    if let index = arguments.firstIndex(of: "-test-enumeration-output-path"),
                       index + 1 < arguments.count
                    {
                        try? json.write(toFile: arguments[index + 1], atomically: true, encoding: .utf8)
                    }
                    return AsyncThrowingStream { continuation in continuation.finish() }
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
            givenEnumeration(json: enumerationJSON([
                ("AppTests", ["LoginTests", "SignupTests"]),
                ("CoreTests", ["NetworkTests"]),
            ]))

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: nil,
                onlyTesting: []
            )

            let appTests = result.first { $0.blueprintName == "AppTests" }
            #expect(appTests?.onlyTestIdentifiers == ["LoginTests", "SignupTests"])
            let coreTests = result.first { $0.blueprintName == "CoreTests" }
            #expect(coreTests?.onlyTestIdentifiers == ["NetworkTests"])
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_capturesSwiftTestingSuitesByTypeName() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            // Swift Testing suites are reported with `kind == "class"` and their type name (not the
            // `@Suite("display name")`), so they shard with valid `-only-testing` identifiers.
            givenEnumeration(json: enumerationJSON([
                ("FeatureTests", ["GammaSuite", "DeltaSuite"]),
            ]))

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: nil,
                onlyTesting: []
            )

            #expect(result == [XCTestRun.TestTarget(
                blueprintName: "FeatureTests",
                onlyTestIdentifiers: ["GammaSuite", "DeltaSuite"]
            )])
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_requestsJSONOutputToAFile() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            let captured = ArgumentsBox()
            givenEnumeration(json: enumerationJSON([("AppTests", ["LoginTests"])]), capturing: captured)

            _ = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: nil,
                onlyTesting: []
            )

            let arguments = captured.value
            #expect(arguments.contains("-enumerate-tests"))
            #expect(consecutive(arguments, "-test-enumeration-format", "json"))
            #expect(consecutive(arguments, "-test-enumeration-style", "hierarchical"))
            #expect(arguments.contains("-test-enumeration-output-path"))
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_withDestination_passesDestination() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            let captured = ArgumentsBox()
            givenEnumeration(json: enumerationJSON([("UITests", ["SnapshotTests"])]), capturing: captured)

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: "platform=iOS Simulator,name=iPhone 16",
                onlyTesting: []
            )

            #expect(consecutive(captured.value, "-destination", "platform=iOS Simulator,name=iPhone 16"))
            let uiTests = result.first { $0.blueprintName == "UITests" }
            #expect(uiTests?.onlyTestIdentifiers == ["SnapshotTests"])
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_targetWithNoClasses_isReportedAsEnumeratedButEmpty() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            givenEnumeration(json: enumerationJSON([("EmptyTarget", [])]))

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: nil,
                onlyTesting: []
            )

            // An enumerated-but-empty target must be reported (with no identifiers) rather than dropped, so
            // callers can tell it apart from a target that failed to enumerate entirely.
            #expect(result == [XCTestRun.TestTarget(blueprintName: "EmptyTarget", onlyTestIdentifiers: [])])
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_throwsEnumerationFailedWhenCommandFails() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            givenCommandError("something went wrong")

            await #expect(throws: XCTestEnumeratorError.self) {
                try await subject.enumerateTests(
                    testProductsPath: testProductsPath,
                    destination: nil,
                    onlyTesting: []
                )
            }
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_throwsWhenOutputIsMalformed() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            givenEnumeration(json: "this is not json")

            await #expect(throws: XCTestEnumeratorError.self) {
                try await subject.enumerateTests(
                    testProductsPath: testProductsPath,
                    destination: nil,
                    onlyTesting: []
                )
            }
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_returnsEmptyWhenNoTargetsEnumerated() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            givenEnumeration(json: #"{"errors":[],"values":[{"kind":"plan","name":"P","children":[]}]}"#)

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: nil,
                onlyTesting: []
            )

            #expect(result.isEmpty)
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_multipleTargets() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            givenEnumeration(json: enumerationJSON([
                ("TargetA", ["SuiteA"]),
                ("TargetB", ["SuiteB"]),
            ]))

            let result = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: nil,
                onlyTesting: []
            )

            let targetA = result.first { $0.blueprintName == "TargetA" }
            #expect(targetA?.onlyTestIdentifiers == ["SuiteA"])
            let targetB = result.first { $0.blueprintName == "TargetB" }
            #expect(targetB?.onlyTestIdentifiers == ["SuiteB"])
        }

        @Test(.inTemporaryDirectory)
        func enumerateTests_withOnlyTesting_passesOnlyTestingArgumentsPerIdentifier() async throws {
            let testProductsPath = try #require(FileSystem.temporaryTestDirectory)
            let capturedArguments = ArgumentsBox()
            givenEnumeration(json: enumerationJSON([]), capturing: capturedArguments)

            _ = try await subject.enumerateTests(
                testProductsPath: testProductsPath,
                destination: nil,
                onlyTesting: ["AppTests", "FeatureTests"]
            )

            let arguments = capturedArguments.value
            #expect(arguments.contains("-enumerate-tests"))
            var onlyTestingValues: [String] = []
            for (index, argument) in arguments.enumerated() where argument == "-only-testing" && index + 1 < arguments.count {
                onlyTestingValues.append(arguments[index + 1])
            }
            #expect(onlyTestingValues.sorted() == ["AppTests", "FeatureTests"])
        }

        /// Returns true if `value` immediately follows `flag` in `arguments`.
        private func consecutive(_ arguments: [String], _ flag: String, _ value: String) -> Bool {
            for (index, argument) in arguments.enumerated() where argument == flag && index + 1 < arguments.count {
                if arguments[index + 1] == value { return true }
            }
            return false
        }
    }

    private final class ArgumentsBox: @unchecked Sendable {
        var value: [String] = []
    }
#endif
