import Foundation

public struct Task: Codable {
    public let options: [Option]
    public let task: ([String: String]) throws -> Void

    public enum Option: Codable, Equatable {
        case required(String)
        case optional(String)

        public var isOptional: Bool {
            switch self {
            case .required:
                return false
            case .optional:
                return true
            }
        }

        public var name: String {
            switch self {
            case let .required(name):
                return name
            case let .optional(name):
                return name
            }
        }

        enum CodingKeys: String, CodingKey {
            case type
            case name
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let name = try container.decode(String.self, forKey: .name)
            let type = try container.decode(String.self, forKey: .type)
            if type == "required" {
                self = .required(name)
            } else if type == "optional" {
                self = .optional(name)
            } else {
                fatalError("Argument '\(type)' not supported")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case let .required(name):
                try container.encode("required", forKey: .type)
                try container.encode(name, forKey: .name)
            case let .optional(name):
                try container.encode("optional", forKey: .type)
                try container.encode(name, forKey: .name)
            }
        }
    }

    public init(
        options: [Option],
        task: @escaping ([String: String]) throws -> Void
    ) {
        self.options = options
        self.task = task
    }

    private enum CodingKeys: String, CodingKey {
        case options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        options = try container.decode([Option].self, forKey: .options)
        // Decoding loses information about the task's function
        // This is fine as we should never invoke `task` directly but using `swiftc` command instead
        task = { _ in }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(options, forKey: .options)
    }
}
