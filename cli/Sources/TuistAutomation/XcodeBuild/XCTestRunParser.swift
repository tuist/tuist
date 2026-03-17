#if os(macOS)
    import FileSystem
    import Foundation
    import Mockable
    import Path

    @Mockable
    public protocol XCTestRunParsing {
        func parseTestModules(xctestrunPath: AbsolutePath) async throws -> [String]
        func parseTestSuites(xctestrunPath: AbsolutePath) async throws -> [String: [String]]
        func findXCTestRunPath(in xctestproductsPath: AbsolutePath) async throws -> AbsolutePath
    }

    public enum XCTestRunParserError: LocalizedError, Equatable {
        case invalidFormat(String)
        case xctestrunNotFound(AbsolutePath)

        public var errorDescription: String? {
            switch self {
            case let .invalidFormat(message):
                return "The .xctestrun file has an invalid format: \(message)"
            case let .xctestrunNotFound(path):
                return "No .xctestrun file found in \(path.pathString)"
            }
        }
    }

    private struct XCTestRunPlist: Decodable {
        let testConfigurations: [TestConfiguration]

        enum CodingKeys: String, CodingKey {
            case testConfigurations = "TestConfigurations"
        }

        struct TestConfiguration: Decodable {
            let testTargets: [TestTarget]?

            enum CodingKeys: String, CodingKey {
                case testTargets = "TestTargets"
            }
        }

        struct TestTarget: Decodable {
            let blueprintName: String
            let onlyTestIdentifiers: [String]?

            enum CodingKeys: String, CodingKey {
                case blueprintName = "BlueprintName"
                case onlyTestIdentifiers = "OnlyTestIdentifiers"
            }
        }
    }

    public struct XCTestRunParser: XCTestRunParsing {
        private let fileSystem: FileSysteming

        public init(fileSystem: FileSysteming = FileSystem()) {
            self.fileSystem = fileSystem
        }

        public func parseTestModules(xctestrunPath: AbsolutePath) async throws -> [String] {
            let plist: XCTestRunPlist = try await readPlist(at: xctestrunPath)
            return plist.testConfigurations
                .flatMap { $0.testTargets ?? [] }
                .map(\.blueprintName)
        }

        public func parseTestSuites(xctestrunPath: AbsolutePath) async throws -> [String: [String]] {
            let plist: XCTestRunPlist = try await readPlist(at: xctestrunPath)
            return plist.testConfigurations
                .flatMap { $0.testTargets ?? [] }
                .reduce(into: [String: [String]]()) { result, target in
                    if let identifiers = target.onlyTestIdentifiers {
                        result[target.blueprintName] = identifiers
                    }
                }
        }

        public func findXCTestRunPath(in xctestproductsPath: AbsolutePath) async throws -> AbsolutePath {
            let matches = try await fileSystem.glob(directory: xctestproductsPath, include: ["**/*.xctestrun"]).collect()
            guard let first = matches.first else {
                throw XCTestRunParserError.xctestrunNotFound(xctestproductsPath)
            }
            return first
        }

        private func readPlist<T: Decodable>(at path: AbsolutePath) async throws -> T {
            do {
                return try await fileSystem.readPlistFile(at: path)
            } catch {
                throw XCTestRunParserError.invalidFormat(error.localizedDescription)
            }
        }
    }
#endif
