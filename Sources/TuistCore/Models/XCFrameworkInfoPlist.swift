import Basic
import Foundation

public struct XCFrameworkInfoPlist: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case libraries = "AvailableLibraries"
    }

    public struct Library: Codable, Equatable {
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

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(identifier, forKey: .identifier)
            try container.encode(path, forKey: .path)
            try container.encode(architectures, forKey: .architectures)
        }
    }

    public let libraries: [Library]
}
