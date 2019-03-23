import Foundation

// MARK: - Workspace

public class Workspace: Codable {
    /// Name of the workspace
    public let name: String

    /// List of project relative paths (or glob patterns) to generate and include
    public let projects: [String]

    /// List of files to include in the workspace (e.g. Documentation)
    public let additionalFiles: [Element]

    /// Workspace
    ///
    /// This can be used to customize the generated workspace.
    ///
    /// - Parameters:
    ///   - name: Name of the workspace.
    ///   - projects: List of project relative paths (or glob patterns) to generate and include.
    ///   - additionalFiles: List of files to include in the workspace (e.g. Documentation)
    public init(name: String, projects: [String], additionalFiles: [Element] = []) {
        self.name = name
        self.projects = projects
        self.additionalFiles = additionalFiles
        dumpIfNeeded(self)
    }
}

extension Workspace {
    public enum Element: Codable {
        /// A glob pattern of files to include
        case glob(pattern: String)

        /// Relative path to a directory to include
        /// as a folder reference
        case folderReference(path: String)

        private enum TypeName: String, Codable {
            case glob
            case folderReference
        }

        private var typeName: TypeName {
            switch self {
            case .glob:
                return .glob
            case .folderReference:
                return .folderReference
            }
        }

        public enum CodingKeys: String, CodingKey {
            case type
            case pattern
            case path
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(TypeName.self, forKey: .type)
            switch type {
            case .glob:
                let pattern = try container.decode(String.self, forKey: .pattern)
                self = .glob(pattern: pattern)
            case .folderReference:
                let path = try container.decode(String.self, forKey: .path)
                self = .folderReference(path: path)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeName, forKey: .type)
            switch self {
            case let .glob(pattern: pattern):
                try container.encode(pattern, forKey: .pattern)
            case let .folderReference(path: path):
                try container.encode(path, forKey: .path)
            }
        }
    }
}

extension Workspace.Element: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .glob(pattern: value)
    }
}
