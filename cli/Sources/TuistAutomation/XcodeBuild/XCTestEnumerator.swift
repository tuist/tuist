#if os(macOS)
    import Command
    import Foundation
    import Mockable
    import Path
    import TuistSupport

    @Mockable
    public protocol XCTestEnumerating {
        /// Enumerates tests in the given test products using `xcodebuild -enumerate-tests`.
        /// - Parameters:
        ///   - testProductsPath: Path to the `.xctestproducts` bundle.
        ///   - destination: An optional xcodebuild destination string (e.g. `"platform=iOS Simulator,name=iPhone 16"`).
        /// - Returns: An array of test targets, each containing the target name and its test suite names.
        func enumerateTests(
            testProductsPath: AbsolutePath,
            destination: String?
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

        public init(commandRunner: CommandRunning = CommandRunner()) {
            self.commandRunner = commandRunner
        }

        public func enumerateTests(
            testProductsPath: AbsolutePath,
            destination: String?
        ) async throws -> [XCTestRun.TestTarget] {
            var arguments = [
                "xcodebuild",
                "test-without-building",
                "-enumerate-tests",
                "-testProductsPath", testProductsPath.pathString,
            ]
            if let destination {
                arguments.append(contentsOf: ["-destination", destination])
            }

            let output: String
            do {
                output = try await commandRunner.run(arguments: arguments).concatenatedString()
            } catch {
                throw XCTestEnumeratorError
                    .enumerationFailed("\(testProductsPath.pathString): \(error.localizedDescription)")
            }

            return parseEnumerationOutput(output)
        }

        /// Parses the text output of `xcodebuild -enumerate-tests -testProductsPath`.
        /// Format: tab-indented lines: `Target <name>` → `Class <name>` → `Test <name>()`
        private func parseEnumerationOutput(_ output: String) -> [XCTestRun.TestTarget] {
            var targets: [String: [String]] = [:]
            var currentTarget: String?

            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("Class ") {
                    let className = String(trimmed.dropFirst("Class ".count))
                    if let target = currentTarget {
                        targets[target, default: []].append(className)
                    }
                } else if trimmed.hasPrefix("Target ") {
                    currentTarget = String(trimmed.dropFirst("Target ".count))
                }
            }

            return targets.map { targetName, classNames in
                XCTestRun.TestTarget(blueprintName: targetName, onlyTestIdentifiers: classNames)
            }
        }
    }

#endif
