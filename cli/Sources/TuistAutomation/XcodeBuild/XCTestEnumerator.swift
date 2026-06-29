#if os(macOS)
    import Command
    import FileSystem
    import Foundation
    import Mockable
    import Path
    import TuistSupport

    @Mockable
    public protocol XCTestEnumerating {
        /// Enumerates tests in the given test products using `xcodebuild -enumerate-tests`.
        ///
        /// The enumeration is requested as machine-parseable JSON written to a file
        /// (`-test-enumeration-format json -test-enumeration-style hierarchical -test-enumeration-output-path`)
        /// rather than scraped from stdout: a large hierarchical text dump streamed over a pipe is prone to
        /// truncation/interleaving, which silently dropped targets from the shard plan.
        /// - Parameters:
        ///   - testProductsPath: Path to the `.xctestproducts` bundle.
        ///   - destination: An xcodebuild destination string (e.g. `"platform=iOS Simulator,name=iPhone 16"`).
        ///     A destination is required by `-enumerate-tests`; pass a concrete one for stable results.
        ///   - onlyTesting: xcodebuild `-only-testing` identifiers (typically module names) restricting which
        ///     targets are enumerated. Pass an empty array to enumerate everything. Used to re-enumerate a
        ///     single module in isolation when a bulk pass drops it.
        /// - Returns: An array of test targets, each containing the target name and its test suite names (XCTest
        ///   classes and Swift Testing suites alike). A target that was enumerated but contains no tests is
        ///   returned with an empty `onlyTestIdentifiers`, so callers can distinguish it from a target that
        ///   failed to enumerate (absent entirely).
        func enumerateTests(
            testProductsPath: AbsolutePath,
            destination: String?,
            onlyTesting: [String]
        ) async throws -> [XCTestRun.TestTarget]
    }

    public enum XCTestEnumeratorError: LocalizedError, Equatable {
        case enumerationFailed(String)

        public var errorDescription: String? {
            switch self {
            case let .enumerationFailed(message):
                return "Test enumeration failed: \(message)"
            }
        }
    }

    public struct XCTestEnumerator: XCTestEnumerating {
        private let commandRunner: CommandRunning
        private let fileSystem: FileSysteming

        public init(
            commandRunner: CommandRunning = CommandRunner(),
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.commandRunner = commandRunner
            self.fileSystem = fileSystem
        }

        public func enumerateTests(
            testProductsPath: AbsolutePath,
            destination: String?,
            onlyTesting: [String]
        ) async throws -> [XCTestRun.TestTarget] {
            try await fileSystem.runInTemporaryDirectory(prefix: "tuist-test-enumeration") { temporaryDirectory in
                let outputPath = temporaryDirectory.appending(component: "enumeration.json")

                var arguments = [
                    "xcodebuild",
                    "test-without-building",
                    "-enumerate-tests",
                    "-test-enumeration-format", "json",
                    "-test-enumeration-style", "hierarchical",
                    "-test-enumeration-output-path", outputPath.pathString,
                    "-testProductsPath", testProductsPath.pathString,
                ]
                if let destination {
                    arguments.append(contentsOf: ["-destination", destination])
                }
                for identifier in onlyTesting {
                    arguments.append(contentsOf: ["-only-testing", identifier])
                }

                do {
                    _ = try await commandRunner.run(arguments: arguments).concatenatedString()
                } catch {
                    throw XCTestEnumeratorError
                        .enumerationFailed("\(testProductsPath.pathString): \(error.localizedDescription)")
                }

                let data: Data
                do {
                    data = try await fileSystem.readFile(at: outputPath)
                } catch {
                    // A missing output file means the enumeration did not complete. Surface it rather than
                    // returning an empty (and therefore silently incomplete) set of targets.
                    throw XCTestEnumeratorError.enumerationFailed(
                        "\(testProductsPath.pathString): enumeration produced no output file (\(error.localizedDescription))"
                    )
                }

                return try parseEnumerationOutput(data, context: testProductsPath.pathString)
            }
        }

        // MARK: - JSON model

        private struct EnumerationOutput: Decodable {
            let values: [Node]
        }

        private struct Node: Decodable {
            let kind: String
            let name: String
            let children: [Node]?
        }

        /// Parses the JSON output of `xcodebuild -enumerate-tests` (hierarchical style). The hierarchy is
        /// `plan → target → class → test`; each `target` node becomes a `TestTarget` whose identifiers are its
        /// `class` children (XCTest classes and Swift Testing suites are both reported with `kind == "class"`).
        /// Targets appearing under multiple plans are merged, preserving first-seen order and de-duplicating
        /// suites. A target with no `class` children is reported with an empty identifier list so callers can
        /// tell an enumerated-but-empty target apart from one that never enumerated.
        private func parseEnumerationOutput(_ data: Data, context: String) throws -> [XCTestRun.TestTarget] {
            let output: EnumerationOutput
            do {
                output = try JSONDecoder().decode(EnumerationOutput.self, from: data)
            } catch {
                throw XCTestEnumeratorError.enumerationFailed(
                    "\(context): could not parse enumeration output (\(error.localizedDescription))"
                )
            }

            var suitesByTarget: [String: [String]] = [:]
            var order: [String] = []

            func visit(_ node: Node) {
                if node.kind == "target" {
                    if suitesByTarget[node.name] == nil {
                        order.append(node.name)
                        suitesByTarget[node.name] = []
                    }
                    for child in node.children ?? [] where child.kind == "class" {
                        if !suitesByTarget[node.name]!.contains(child.name) {
                            suitesByTarget[node.name]!.append(child.name)
                        }
                    }
                } else {
                    for child in node.children ?? [] {
                        visit(child)
                    }
                }
            }

            for node in output.values {
                visit(node)
            }

            return order.map { XCTestRun.TestTarget(blueprintName: $0, onlyTestIdentifiers: suitesByTarget[$0] ?? []) }
        }
    }

#endif
