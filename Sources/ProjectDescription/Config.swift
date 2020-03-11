import Foundation

public typealias TuistConfig = Config

/// This model allows to configure Tuist.
public struct Config: Codable, Equatable {
    /// Contains options related to the project generation.
    ///
    /// - xcodeProjectName(TemplateString): When passed, Tuist generates the project with the specific name on disk instead of using the project name.
    public enum GenerationOptions: Encodable, Decodable, Equatable {
        case xcodeProjectName(TemplateString)
    }

    /// Generation options.
    public let generationOptions: [GenerationOptions]

    /// List of Xcode versions that the project supports.
    public let compatibleXcodeVersions: CompatibleXcodeVersions

    /// URL to the server that caching and insights will interact with.
    public let cloudURL: String?

    /// Initializes the tuist cofiguration.
    ///
    /// - Parameters:
    ///   - compatibleXcodeVersions: List of Xcode versions the project is compatible with.
    ///   - cloudURL: URL to the server that caching and insights will interact with.
    ///   - generationOptions: List of Xcode versions that the project supports. An empty list means that
    public init(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                cloudURL: String? = nil,
                generationOptions: [GenerationOptions]) {
        self.compatibleXcodeVersions = compatibleXcodeVersions
        self.generationOptions = generationOptions
        self.cloudURL = cloudURL
        dumpIfNeeded(self)
    }
}

extension Config.GenerationOptions {
    enum CodingKeys: String, CodingKey {
        case xcodeProjectName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.allKeys.contains(.xcodeProjectName), try container.decodeNil(forKey: .xcodeProjectName) == false {
            var associatedValues = try container.nestedUnkeyedContainer(forKey: .xcodeProjectName)
            let templateProjectName = try associatedValues.decode(TemplateString.self)
            self = .xcodeProjectName(templateProjectName)
            return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown enum case"))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .xcodeProjectName(templateProjectName):
            var associatedValues = container.nestedUnkeyedContainer(forKey: .xcodeProjectName)
            try associatedValues.encode(templateProjectName)
        }
    }
}
