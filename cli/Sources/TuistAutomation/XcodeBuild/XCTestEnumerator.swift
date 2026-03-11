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

    public enum XCTestEnumeratorError: LocalizedError {
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

            return try parseEnumerationOutput(result.standardOutput)
        }

        private func parseEnumerationOutput(_ output: String) throws -> [String: [String]] {
            guard let data = output.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = json["values"] as? [[String: Any]]
            else {
                throw XCTestEnumeratorError.invalidOutput
            }

            var result: [String: [String]] = [:]

            for entry in values {
                guard let subtests = entry["subtests"] as? [[String: Any]] else { continue }
                for target in subtests {
                    guard let targetName = target["name"] as? String,
                          let targetSubtests = target["subtests"] as? [[String: Any]]
                    else { continue }

                    var suites: [String] = []
                    for suite in targetSubtests {
                        if let suiteName = suite["name"] as? String {
                            suites.append(suiteName)
                        }
                    }
                    result[targetName] = suites
                }
            }

            return result
        }
    }
#endif
