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
        /// - Returns: An ``XCTestEnumeration`` with the enumerated targets and any `errors` xcodebuild
        ///   reported. A target that was enumerated but contains no tests is returned with an empty
        ///   `onlyTestIdentifiers`; a target xcodebuild listed but could not boot/test is *also* reported
        ///   present-but-empty, but accompanied by an entry in `errors` — so callers can tell a genuinely
        ///   empty target apart from one whose tests could not be discovered.
        func enumerateTests(
            testProductsPath: AbsolutePath,
            destination: String?,
            onlyTesting: [String]
        ) async throws -> XCTestEnumeration
    }

    /// The result of an `xcodebuild -enumerate-tests` pass.
    public struct XCTestEnumeration: Equatable {
        /// The enumerated test targets. A target with no discovered tests is present with an empty
        /// `onlyTestIdentifiers` rather than omitted.
        public let targets: [XCTestRun.TestTarget]

        /// Free-form errors xcodebuild reported for targets it listed but could not test (for example a
        /// target that failed to boot). Non-empty when at least one target could not be enumerated, even
        /// though it may still appear in `targets` as present-but-empty.
        public let errors: [String]

        public init(targets: [XCTestRun.TestTarget], errors: [String] = []) {
            self.targets = targets
            self.errors = errors
        }
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
        ) async throws -> XCTestEnumeration {
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
            let errors: [String]?
        }

        private struct Node: Decodable {
            let kind: String
            let name: String
            let children: [Node]?
        }

        /// Parses the JSON output of `xcodebuild -enumerate-tests` (hierarchical style). The hierarchy is
        /// `plan → target → class → test`; each `target` node becomes a `TestTarget`. A target's
        /// `-only-testing` identifiers are its direct `class` children (XCTest classes and Swift Testing
        /// `@Suite` types, both reported as `kind == "class"`) *and* its direct `test` children (top-level
        /// Swift Testing `@Test` functions that have no enclosing suite, reported as `kind == "test"` directly
        /// under the target). Both forms are emitted with names that are valid `-only-testing` identifiers.
        /// Targets appearing under multiple plans are merged, preserving first-seen order and de-duplicating
        /// identifiers. A target with no such children is reported with an empty identifier list so callers
        /// can tell an enumerated-but-empty target apart from one that never enumerated.
        ///
        /// The top-level `errors` array — which xcodebuild populates for targets it lists but cannot boot or
        /// test — is surfaced verbatim so callers can distinguish a genuinely empty target from one whose
        /// tests simply could not be discovered.
        private func parseEnumerationOutput(_ data: Data, context: String) throws -> XCTestEnumeration {
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
                    // A target's shardable units are its direct `class` children (XCTest classes / Swift
                    // Testing `@Suite` types) and its direct `test` children (top-level `@Test` functions with
                    // no enclosing suite). Tests nested inside a class are intentionally not collected — we
                    // shard at suite granularity, not individual test methods.
                    for child in node.children ?? [] where child.kind == "class" || child.kind == "test" {
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

            let targets = order.map {
                XCTestRun.TestTarget(blueprintName: $0, onlyTestIdentifiers: suitesByTarget[$0] ?? [])
            }
            return XCTestEnumeration(targets: targets, errors: output.errors ?? [])
        }
    }

#endif
