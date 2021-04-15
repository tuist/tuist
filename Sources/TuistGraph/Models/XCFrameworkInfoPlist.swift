import Foundation
import TSCBasic

/// It represents th Info.plist contained in an .xcframework bundle.
public struct XCFrameworkInfoPlist: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case libraries = "AvailableLibraries"
    }

    /// It represents a library inside an .xcframework
    public struct Library: Codable, Equatable {
        private enum CodingKeys: String, CodingKey {
            case identifier = "LibraryIdentifier"
            case path = "LibraryPath"
            case architectures = "SupportedArchitectures"
        }

        /// It represents the library's platform.
        public enum Platform: String, Codable {
            case ios
        }

        /// Library identifier.
        public let identifier: String

        /// Path to the library.
        public let path: RelativePath

        /// Architectures the binary is built for.
        public let architectures: [BinaryArchitecture]

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(identifier, forKey: .identifier)
            try container.encode(path, forKey: .path)
            try container.encode(architectures, forKey: .architectures)
        }
    }

    /// List of libraries that are part of the .xcframework.
    public let libraries: [Library]
}
