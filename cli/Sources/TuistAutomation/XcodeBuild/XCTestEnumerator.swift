#if os(macOS)
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
        /// - Returns: A dictionary mapping each test target name to its list of test suite names.
        func enumerateTests(
            testProductsPath: AbsolutePath,
            scheme: String,
            destination: String?
        ) async throws -> [String: [String]]
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
        private let system: Systeming

        public init(system: Systeming = System.shared) {
            self.system = system
        }

        public func enumerateTests(
            testProductsPath: AbsolutePath,
            scheme: String,
            destination: String?
        ) async throws -> [String: [String]] {
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

            let result: SystemCollectedOutput
            do {
                result = try await system.runAndCollectOutput(arguments)
            } catch {
                throw XCTestEnumeratorError.enumerationFailed(error.localizedDescription)
            }

            guard let data = result.standardOutput.data(using: .utf8) else {
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
                .reduce(into: [String: [String]]()) { result, target in
                    result[target.name] = target.subtests?.map(\.name) ?? []
                }
        }
    }
#endif
