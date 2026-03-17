#if os(macOS)
    import Foundation
    import Mockable
    import Path
    import TuistSupport

    @Mockable
    public protocol XCTestEnumerating {
        func enumerateTests(
            testProductsPath: AbsolutePath,
            scheme: String,
            destination: String?
        ) async throws -> [String: [String]]
    }

    public enum XCTestEnumeratorError: LocalizedError, Equatable {
        case enumerationFailed(String)
        case invalidOutput

        public var errorDescription: String? {
            switch self {
            case let .enumerationFailed(message):
                return "Test enumeration failed: \(message)"
            case .invalidOutput:
                return "Could not parse test enumeration output."
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
        public init() {}

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
                result = try await System.shared.runAndCollectOutput(arguments)
            } catch {
                throw XCTestEnumeratorError.enumerationFailed(error.localizedDescription)
            }

            guard let data = result.standardOutput.data(using: .utf8) else {
                throw XCTestEnumeratorError.invalidOutput
            }

            let enumerated: EnumeratedTests
            do {
                enumerated = try JSONDecoder().decode(EnumeratedTests.self, from: data)
            } catch {
                throw XCTestEnumeratorError.invalidOutput
            }

            return enumerated.values
                .flatMap { $0.subtests ?? [] }
                .reduce(into: [String: [String]]()) { result, target in
                    result[target.name] = target.subtests?.map(\.name) ?? []
                }
        }
    }
#endif
