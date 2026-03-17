#if os(macOS)
    import Foundation
    import Mockable
    import Path

    @Mockable
    public protocol XCTestRunParsing {
        func parseTestModules(xctestrunPath: AbsolutePath) throws -> [String]
        func parseTestSuites(xctestrunPath: AbsolutePath) throws -> [String: [String]]
        func findXCTestRunPath(in xctestproductsPath: AbsolutePath) throws -> AbsolutePath
    }

    public enum XCTestRunParserError: LocalizedError, Equatable {
        case cannotReadFile(AbsolutePath)
        case invalidFormat(String)
        case xctestrunNotFound(AbsolutePath)

        public var errorDescription: String? {
            switch self {
            case let .cannotReadFile(path):
                return "Cannot read .xctestrun file at \(path.pathString)"
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
        public init() {}

        public func parseTestModules(xctestrunPath: AbsolutePath) throws -> [String] {
            let plist = try decodePlist(at: xctestrunPath)
            return plist.testConfigurations
                .flatMap { $0.testTargets ?? [] }
                .map(\.blueprintName)
        }

        public func parseTestSuites(xctestrunPath: AbsolutePath) throws -> [String: [String]] {
            let plist = try decodePlist(at: xctestrunPath)
            return plist.testConfigurations
                .flatMap { $0.testTargets ?? [] }
                .reduce(into: [String: [String]]()) { result, target in
                    if let identifiers = target.onlyTestIdentifiers {
                        result[target.blueprintName] = identifiers
                    }
                }
        }

        public func findXCTestRunPath(in xctestproductsPath: AbsolutePath) throws -> AbsolutePath {
            let fileManager = FileManager.default
            let basePath = xctestproductsPath.pathString

            guard let enumerator = fileManager.enumerator(atPath: basePath) else {
                throw XCTestRunParserError.xctestrunNotFound(xctestproductsPath)
            }

            while let relativePath = enumerator.nextObject() as? String {
                if relativePath.hasSuffix(".xctestrun") {
                    return try AbsolutePath(validating: "\(basePath)/\(relativePath)")
                }
            }

            throw XCTestRunParserError.xctestrunNotFound(xctestproductsPath)
        }

        private func decodePlist(at path: AbsolutePath) throws -> XCTestRunPlist {
            let data: Data
            do {
                data = try Data(contentsOf: URL(fileURLWithPath: path.pathString))
            } catch {
                throw XCTestRunParserError.cannotReadFile(path)
            }
            do {
                return try PropertyListDecoder().decode(XCTestRunPlist.self, from: data)
            } catch {
                throw XCTestRunParserError.invalidFormat(error.localizedDescription)
            }
        }
    }
#endif
