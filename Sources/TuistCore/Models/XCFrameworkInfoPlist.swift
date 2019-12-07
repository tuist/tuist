import Basic
import Foundation

public struct XCFrameworkInfoPlist: Codable {
    
    enum CodingKeys: String, CodingKey {
        case libraries = "AvailableLibraries"
    }

    public struct Library: Codable {
    
         enum CodingKeys: String, CodingKey {
               case identifier = "LibraryIdentifier"
               case path = "LibraryPath"
               case architectures = "SupportedArchitectures"
        }

        public enum Platform: String, Codable {
            case ios
        }
        
        public let identifier: String
        public let path: RelativePath
        public let architectures: [BinaryArchitecture]
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            identifier = try container.decode(String.self, forKey: .identifier)
            path = try container.decode(RelativePath.self, forKey: .path)
            architectures = try container.decode([BinaryArchitecture].self, forKey: .architectures)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(identifier, forKey: .identifier)
            try container.encode(path, forKey: .path)
            try container.encode(architectures, forKey: .architectures)
        }
    }

    public let libraries: [Library]
}
