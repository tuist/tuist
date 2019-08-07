import Foundation

/// This model allows to configure Tuist.
public class TuistConfig: Encodable, Decodable, Equatable {
    /// Contains options related to the project generation.
    ///
    /// - generateManifestElement: When passed, Tuist generates the projects, targets and schemes to compile the project manifest.
    /// - xcodeProjectName(TemplateString): When passed, Tuist generates the project with the specific name on disk instead of using the project name.
    public enum GenerationOptions: Encodable, Decodable, Equatable {
        case generateManifest
        case xcodeProjectName(TemplateString)
    }

    /// Generation options.
    public let generationOptions: [GenerationOptions]

    /// List of Xcode versions that the project supports.
    public let compatibleXcodeVersions: CompatibleXcodeVersions

    /// Initializes the tuist cofiguration.
    ///
    /// - Parameters:
    ///   - compatibleXcodeVersions: .
    ///   - generationOptions: List of Xcode versions that the project supports. An empty list means that
    public init(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                generationOptions: [GenerationOptions]) {
        self.generationOptions = generationOptions
        self.compatibleXcodeVersions = compatibleXcodeVersions
        dumpIfNeeded(self)
    }
}

extension TuistConfig.GenerationOptions {
    enum CodingKeys: String, CodingKey {
        case generateManifest
        case xcodeProjectName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.allKeys.contains(.generateManifest), try container.decodeNil(forKey: .generateManifest) == false {
            self = .generateManifest
            return
        }
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
        case .generateManifest:
            _ = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .generateManifest)
        case let .xcodeProjectName(templateProjectName):
            var associatedValues = container.nestedUnkeyedContainer(forKey: .xcodeProjectName)
            try associatedValues.encode(templateProjectName)
        }
    }
}

public func == (lhs: TuistConfig, rhs: TuistConfig) -> Bool {
    guard lhs.generationOptions == rhs.generationOptions else { return false }
    return true
}

public func == (lhs: TuistConfig.GenerationOptions, rhs: TuistConfig.GenerationOptions) -> Bool {
    switch (lhs, rhs) {
    case (.generateManifest, .generateManifest):
        return true
    case let (.xcodeProjectName(lhs), .xcodeProjectName(rhs)):
        return lhs.rawString == rhs.rawString
    default: return false
    }
}
