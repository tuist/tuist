import Foundation

// MARK: - Workspace

public class Workspace: Codable {
    public indirect enum Element: Codable {
        case file(path: String)
        case group(name: String, contents: [Element])
        case project(path: String)
    }

    // Workspace name
    public let name: String

    // Elements displayed in the workspace. These can be files, groups which can
    // contain other references or other tuist projects.
    public let contents: [Element]

    public init(name: String, contents: [Element]) {
        self.name = name
        self.contents = contents
        dumpIfNeeded(self)
    }

    public init(name: String, projects: [String]) {
        self.name = name
        contents = projects.map(Element.project)
        dumpIfNeeded(self)
    }
}

extension Workspace.Element {
    public enum CodingKeys: String, CodingKey {
        case elementType
        case value
    }

    private enum ElementType: String, Codable {
        case file, group, project
    }

    private var elementType: ElementType {
        switch self {
        case .file: return .file
        case .group: return .group
        case .project: return .project
        }
    }

    private struct FileElement: Codable {
        public let path: String
    }

    private struct GroupElement: Codable {
        public let name: String
        public let contents: [Workspace.Element]
    }

    private struct ProjectElement: Codable {
        public let path: String
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let elementType = try container.decode(ElementType.self, forKey: .elementType)

        switch elementType {
        case .file:
            let element = try container.decode(FileElement.self, forKey: .value)
            self = .file(path: element.path)
        case .group:
            let element = try container.decode(GroupElement.self, forKey: .value)
            self = .group(name: element.name, contents: element.contents)
        case .project:
            let element = try container.decode(ProjectElement.self, forKey: .value)
            self = .project(path: element.path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(elementType, forKey: .elementType)

        switch self {
        case let .file(path: path):
            try container.encode(FileElement(path: path), forKey: .value)
        case let .group(name: name, contents: contents):
            try container.encode(GroupElement(name: name, contents: contents), forKey: .value)
        case let .project(path: path):
            try container.encode(ProjectElement(path: path), forKey: .value)
        }
    }
}
