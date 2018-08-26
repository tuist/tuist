import Foundation

// MARK: - TargetDependency

public enum TargetDependency: Codable {
    case target(name: String)
    case project(target: String, path: String)
    case framework(path: String)
    case library(path: String, publicHeaders: String, swiftModuleMap: String?)

    public var typeName: String {
        switch self {
        case .target:
            return "target"
        case .project:
            return "project"
        case .framework:
            return "framework"
        case .library:
            return "library"
        }
    }
}

// MARK: - TargetDependency (Coding)

extension TargetDependency {
    public enum CodingError: Error {
        case unknownType(String)
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case name
        case target
        case path
        case publicHeaders = "public_headers"
        case swiftModuleMap = "swift_module_map"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "target":
            self = .target(name: try container.decode(String.self, forKey: .name))

        case "project":
            self = .project(
                target: try container.decode(String.self, forKey: .target),
                path: try container.decode(String.self, forKey: .path)
            )

        case "framework":
            self = .framework(path: try container.decode(String.self, forKey: .path))

        case "library":
            self = .library(
                path: try container.decode(String.self, forKey: .path),
                publicHeaders: try container.decode(String.self, forKey: .publicHeaders),
                swiftModuleMap: try container.decodeIfPresent(String.self, forKey: .swiftModuleMap)
            )

        default:
            throw CodingError.unknownType(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(typeName, forKey: .type)

        switch self {
        case let .target(name: name):
            try container.encode(name, forKey: .name)
        case let .project(target: target, path: path):
            try container.encode(target, forKey: .target)
            try container.encode(path, forKey: .path)
        case let .framework(path: path):
            try container.encode(path, forKey: .path)
        case let .library(path: path, publicHeaders: publicHeaders, swiftModuleMap: swiftModuleMap):
            try container.encode(path, forKey: .path)
            try container.encode(publicHeaders, forKey: .publicHeaders)
            try container.encodeIfPresent(swiftModuleMap, forKey: .swiftModuleMap)
        }
    }
}
