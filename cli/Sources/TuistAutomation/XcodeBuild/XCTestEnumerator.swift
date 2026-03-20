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
        ///   - scheme: The Xcode scheme whose tests should be enumerated.
        ///   - destination: An optional xcodebuild destination string (e.g. `"platform=iOS Simulator,name=iPhone 16"`).
        /// - Returns: An array of test targets, each containing the target name and its test suite names.
        func enumerateTests(
            testProductsPath: AbsolutePath,
            scheme: String,
            destination: String?
        ) async throws -> [XCTestRun.TestTarget]
    }

    public enum XCTestEnumeratorError: LocalizedError, Equatable {
        case enumerationFailed(String)
        case invalidOutput(String)

        public var errorDescription: String? {
            switch self {
            case let .enumerationFailed(message):
                return "Test enumeration failed: \(message)"
            case let .invalidOutput(message):
                return "Could not parse test enumeration output: \(message)"
            }
        }
    }

    private struct EnumeratedTests: Decodable {
        let values: [Entry]

        struct Entry: Decodable {
            var subtests: [Target]?
        }

        struct Target: Decodable {
            let name: String
            var subtests: [Suite]?
        }

        struct Suite: Decodable {
            let name: String
        }
    }

    public struct XCTestEnumerator: XCTestEnumerating {
        private let commandRunner: CommandRunning

        public init(commandRunner: CommandRunning = CommandRunner()) {
            self.commandRunner = commandRunner
        }

        public func enumerateTests(
            testProductsPath: AbsolutePath,
            scheme: String,
            destination: String?
        ) async throws -> [XCTestRun.TestTarget] {
            var arguments = [
                "xcodebuild",
                "test-without-building",
                "-enumerate-tests",
                "-testProductsPath", testProductsPath.pathString,
                "-scheme", scheme,
            ]
            if let destination {
                arguments.append(contentsOf: ["-destination", destination])
            }

            let output: String
            do {
                output = try await commandRunner.run(arguments: arguments).concatenatedString()
            } catch {
                throw XCTestEnumeratorError
                    .enumerationFailed("scheme '\(scheme)' at \(testProductsPath.pathString): \(error.localizedDescription)")
            }

            guard let data = output.data(using: .utf8) else {
                throw XCTestEnumeratorError.invalidOutput("Output is not valid UTF-8")
            }

            let enumerated: EnumeratedTests
            do {
                enumerated = try JSONDecoder().decode(EnumeratedTests.self, from: data)
            } catch {
                throw XCTestEnumeratorError.invalidOutput(error.localizedDescription)
            }

            return enumerated.values
                .flatMap { $0.subtests ?? [] }
                .map { XCTestRun.TestTarget(blueprintName: $0.name, onlyTestIdentifiers: $0.subtests?.map(\.name)) }
        }
    }

#endif
