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
            case binaryPath = "BinaryPath"
            case identifier = "LibraryIdentifier"
            case path = "LibraryPath"
            case architectures = "SupportedArchitectures"
            case mergeableMetadata = "MergeableMetadata"
        }

        /// It represents the library's platform.
        public enum Platform: String, Codable {
            case ios
        }

        /// Binary name used to import the library
        public var binaryName: String {
            path.basenameWithoutExt
        }

        /// Library identifier.
        public let identifier: String

        /// Path to the library.
        public let path: RelativePath

        /// Declares if the library is mergeable or not
        public let mergeableMetadata: Bool

        /// Architectures the binary is built for.
        public let architectures: [BinaryArchitecture]

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(identifier, forKey: .identifier)
            try container.encode(path, forKey: .path)
            try container.encode(mergeableMetadata, forKey: .mergeableMetadata)
            try container.encode(architectures, forKey: .architectures)
        }

        public init(
            identifier: String,
            path: RelativePath,
            mergeableMetadata: Bool,
            architectures: [BinaryArchitecture]
        ) {
            self.identifier = identifier
            self.path = path
            self.mergeableMetadata = mergeableMetadata
            self.architectures = architectures
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            identifier = try container.decode(String.self, forKey: .identifier)
            path = try container.decode(RelativePath.self, forKey: .path)
            architectures = try container.decode([BinaryArchitecture].self, forKey: .architectures)
            mergeableMetadata = try container.decodeIfPresent(Bool.self, forKey: .mergeableMetadata) ?? false
        }
    }

    /// List of libraries that are part of the .xcframework.
    public let libraries: [Library]
}
