import Path

public struct Template: Equatable {
    public let description: String
    public let attributes: [Attribute]
    public let items: [Item]

    public init(
        description: String,
        attributes: [Attribute] = [],
        items: [Item] = []
    ) {
        self.description = description
        self.attributes = attributes
        self.items = items
    }

    public enum Attribute: Equatable {
        case required(String)
        case optional(String, default: Value)

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
            case let .optional(name, default: _):
                return name
            }
        }

        public indirect enum Value: Equatable, RawRepresentable {
            case string(String)
            case integer(Int)
            case real(Double)
            case boolean(Bool)
            case dictionary([String: Value])
            case array([Value])

            public typealias RawValue = Any

            public init?(rawValue: RawValue) {
                switch rawValue {
                case is String:
                    if let string = rawValue as? String {
                        self = .string(string)
                    } else {
                        return nil
                    }
                case is Int:
                    if let integer = rawValue as? Int {
                        self = .integer(integer)
                    } else {
                        return nil
                    }
                case is Double:
                    if let real = rawValue as? Double {
                        self = .real(real)
                    } else {
                        return nil
                    }
                case is Bool:
                    if let boolean = rawValue as? Bool {
                        self = .boolean(boolean)
                    } else {
                        return nil
                    }
                case is [String: Any]:
                    if let dictionary = rawValue as? [String: Any] {
                        var newDictionary: [String: Self] = [:]
                        for (key, value) in dictionary {
                            newDictionary[key] = .init(rawValue: value)
                        }
                        self = .dictionary(newDictionary)
                    } else {
                        return nil
                    }
                case is [Any]:
                    if let array = rawValue as? [Any] {
                        let newArray: [Self] = array.map { .init(rawValue: $0) }.compactMap { $0 }
                        self = .array(newArray)
                    } else {
                        return nil
                    }
                default:
                    return nil
                }
            }

            public var rawValue: RawValue {
                switch self {
                case let .string(string):
                    return string
                case let .integer(integer):
                    return integer
                case let .real(real):
                    return real
                case let .boolean(boolean):
                    return boolean
                case let .dictionary(dictionary):
                    var newDictionary: [String: Any] = [:]
                    for (key, value) in dictionary {
                        newDictionary[key] = value.rawValue
                    }
                    return newDictionary
                case let .array(array):
                    let newArray: [Any] = array.map(\.rawValue)
                    return newArray
                }
            }
        }
    }

    public enum Contents: Equatable {
        case string(String)
        case file(AbsolutePath)
        case directory(AbsolutePath)
    }

    public struct Item: Equatable {
        public let path: RelativePath
        public let contents: Contents

        public init(
            path: RelativePath,
            contents: Contents
        ) {
            self.path = path
            self.contents = contents
        }

        #if DEBUG
            public static func test(
                path: RelativePath,
                contents: Template.Contents = .string("test content")
            ) -> Template.Item {
                Template.Item(
                    path: path,
                    contents: contents
                )
            }
        #endif
    }

    #if DEBUG
        public static func test(
            description: String = "Template",
            attributes: [Attribute] = [],
            items: [Template.Item] = []
        ) -> Template {
            Template(
                description: description,
                attributes: attributes,
                items: items
            )
        }
    #endif
}
