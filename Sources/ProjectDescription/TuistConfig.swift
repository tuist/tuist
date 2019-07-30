import Foundation

/// This model allows to configure Tuist.
public class TuistConfig: Encodable, Decodable {
    /// Contains options related to the project generation.
    ///
    /// - generateManifestElement: When passed, Tuist generates the projects, targets and schemes to compile the project manifest.
    public enum GenerationOption: Encodable, Decodable, Equatable {
        case generateManifest
        case suffixProjectNames(with: String)
        case prefixProjectNames(with: String)
    }

    /// Generation options.
    public let generationOptions: [GenerationOption]

    /// Initializes the tuist cofiguration.
    ///
    /// - Parameter generationOptions: Generation options.
    public init(generationOptions: [GenerationOption]) {
        self.generationOptions = generationOptions
        dumpIfNeeded(self)
    }
}

extension TuistConfig.GenerationOption {
    enum CodingKeys: String, CodingKey {
        case generateManifest
        case suffixProjectNames
        case prefixProjectNames
        case with
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.allKeys.contains(.generateManifest), try container.decodeNil(forKey: .generateManifest) == false {
            self = .generateManifest
            return
        }
        if container.allKeys.contains(.suffixProjectNames), try container.decodeNil(forKey: .suffixProjectNames) == false {
            let associatedValues = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .suffixProjectNames)
            let with = try associatedValues.decode(String.self, forKey: .with)
            self = .suffixProjectNames(with: with)
            return
        }
        if container.allKeys.contains(.prefixProjectNames), try container.decodeNil(forKey: .prefixProjectNames) == false {
            let associatedValues = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .prefixProjectNames)
            let with = try associatedValues.decode(String.self, forKey: .with)
            self = .prefixProjectNames(with: with)
            return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown enum case"))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .generateManifest:
            _ = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .generateManifest)
        case let .suffixProjectNames(with):
            var associatedValues = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .suffixProjectNames)
            try associatedValues.encode(with, forKey: .with)
        case let .prefixProjectNames(with):
            var associatedValues = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .prefixProjectNames)
            try associatedValues.encode(with, forKey: .with)
        }
    }
}

public func == (lhs: TuistConfig.GenerationOption, rhs: TuistConfig.GenerationOption) -> Bool {
    switch (lhs, rhs) {
    case (.generateManifest, .generateManifest):
        return true
    case let (.suffixProjectNames(lhs), .suffixProjectNames(rhs)):
        return lhs == rhs
    case let (.prefixProjectNames(lhs), .prefixProjectNames(rhs)):
        return lhs == rhs
    default: return false
    }
}
