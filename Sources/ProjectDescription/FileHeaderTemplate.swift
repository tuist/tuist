import Foundation

public enum FileHeaderTemplate: Codable, Equatable, ExpressibleByStringInterpolation {
    enum CodingKeys: String, CodingKey {
        case file
        case string
    }
    
    case file(Path)
    case string(String)
    
    public init(stringLiteral value: String) {
        self = .string(value)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if container.allKeys.contains(.file), try container.decodeNil(forKey: .file) == false {
            var associatedValues = try container.nestedUnkeyedContainer(forKey: .file)
            let path = try associatedValues.decode(Path.self)
            self = .file(path)
        } else if container.allKeys.contains(.string), try container.decodeNil(forKey: .string) == false {
            var associatedValues = try container.nestedUnkeyedContainer(forKey: .string)
            let string = try associatedValues.decode(String.self)
            self = .string(string)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown enum case"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case let .file(path):
            var associatedValues = container.nestedUnkeyedContainer(forKey: .file)
            try associatedValues.encode(path)
        case let .string(string):
            var associatedValues = container.nestedUnkeyedContainer(forKey: .string)
            try associatedValues.encode(string)
        }
    }
}
