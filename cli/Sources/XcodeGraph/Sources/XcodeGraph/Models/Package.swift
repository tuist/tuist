import Path
import ProjectDescription

public enum Package: Equatable, Codable, Sendable {
    case remote(url: String, requirement: Requirement)
    case local(config: LocalPackageReferenceConfig)

    public var identity: String {
        let value = switch self {
        case let .remote(url, _):
            url.split(separator: "/").last.map(String.init) ?? url
        case let .local(config):
            config.path.basename
        }
        let normalizedValue = value.lowercased()
        return normalizedValue.hasSuffix(".git") ? String(normalizedValue.dropLast(4)) : normalizedValue
    }
}

public struct LocalPackageReferenceConfig: Equatable, Codable, Sendable {
    /// Abitlity to group packages in Xcode Project
    public enum Grouping: Equatable, Codable, Sendable {
        /// Custom path to the Package
        case custom(String)
        /// Path to trimm from original path
        case trimmingPrefix(String)
        /// Path keeps original structure
        case original

        public init?(from grouping: ProjectDescription.Package.LocalPackageReferenceConfig.Grouping?) {
            switch grouping {
            case .custom(let string):
                self = .custom(string)
            case .trimmingPrefix(let string):
                self = .trimmingPrefix(string)
            case .original:
                self = .original
            default:
                return nil
            }
        }
    }

    public let path: AbsolutePath
    public let grouping: Grouping?

    public var isStandardReference: Bool {
        grouping == nil
    }

    /// - Parameters:
    ///    - path: Absolute path of a package
    ///    - grouping: Path which would be used to structure packages in generated project
    public init(path: AbsolutePath, grouping: Grouping? = nil) {
        self.path = path
        self.grouping = grouping
    }
}

extension XcodeGraph.Package {
    public var isRemote: Bool {
        switch self {
        case .remote:
            return true
        case .local:
            return false
        }
    }
}
