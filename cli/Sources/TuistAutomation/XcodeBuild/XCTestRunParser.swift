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

    public enum XCTestRunParserError: LocalizedError {
        case cannotReadFile(AbsolutePath)
        case invalidFormat
        case xctestrunNotFound(AbsolutePath)

        public var errorDescription: String? {
            switch self {
            case let .cannotReadFile(path):
                return "Cannot read .xctestrun file at \(path.pathString)"
            case .invalidFormat:
                return "The .xctestrun file has an invalid format."
            case let .xctestrunNotFound(path):
                return "No .xctestrun file found in \(path.pathString)"
            }
        }
    }

    public struct XCTestRunParser: XCTestRunParsing {
        public init() {}

        public func parseTestModules(xctestrunPath: AbsolutePath) throws -> [String] {
            let plist = try loadPlist(at: xctestrunPath)
            return extractTestModules(from: plist)
        }

        public func parseTestSuites(xctestrunPath: AbsolutePath) throws -> [String: [String]] {
            let plist = try loadPlist(at: xctestrunPath)
            return extractTestTargetIdentifiers(from: plist)
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

        private func loadPlist(at path: AbsolutePath) throws -> [String: Any] {
            let data = try Data(contentsOf: URL(fileURLWithPath: path.pathString))
            guard let plist = try PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: Any] else {
                throw XCTestRunParserError.invalidFormat
            }
            return plist
        }

        private func extractTestModules(from plist: [String: Any]) -> [String] {
            guard let configurations = plist["TestConfigurations"] as? [[String: Any]] else {
                return Array(plist.keys.filter { $0 != "__xctestrun_metadata__" })
            }

            var modules: [String] = []
            for config in configurations {
                guard let targets = config["TestTargets"] as? [[String: Any]] else { continue }
                for target in targets {
                    if let name = target["BlueprintName"] as? String {
                        modules.append(name)
                    }
                }
            }
            return modules
        }

        private func extractTestTargetIdentifiers(from plist: [String: Any]) -> [String: [String]] {
            guard let configurations = plist["TestConfigurations"] as? [[String: Any]] else {
                return [:]
            }

            var result: [String: [String]] = [:]
            for config in configurations {
                guard let targets = config["TestTargets"] as? [[String: Any]] else { continue }
                for target in targets {
                    guard let name = target["BlueprintName"] as? String else { continue }
                    if let identifiers = target["OnlyTestIdentifiers"] as? [String] {
                        result[name] = identifiers
                    }
                }
            }
            return result
        }
    }
#endif
