import Basic
import Foundation
import TuistCore

/// This model allows to configure Tuist.
public class TuistConfig: Equatable, Hashable {
    /// Contains options related to the project generation.
    ///
    /// - generateManifestElement: When passed, Tuist generates the projects, targets and schemes to compile the project manifest.
    public enum GenerationOption: Hashable, Equatable {
        case generateManifest
        case xcodeProjectName(TemplateString)
    }

    /// Generation options.
    public let generationOptions: [GenerationOption]

    /// Returns the default Tuist configuration.
    public static var `default`: TuistConfig {
        return TuistConfig(generationOptions: [.generateManifest])
    }

    /// Initializes the tuist cofiguration.
    ///
    /// - Parameters:
    ///   - generationOptions: Generation options.
    public init(generationOptions: [GenerationOption]) {
        self.generationOptions = generationOptions
    }

    static func at(_ path: AbsolutePath, cache: GraphLoaderCaching, modelLoader: GeneratorModelLoading, fileHandler _: FileHandling) throws -> TuistConfig {
        if let tuistConfig = cache.tuistConfig(path) {
            return tuistConfig
        } else {
            let tuistConfig = try modelLoader.loadTuistConfig(at: path)
            cache.add(tuistConfig: tuistConfig, path: path)
            return tuistConfig
        }
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(generationOptions)
    }

    // MARK: - Equatable

    public static func == (lhs: TuistConfig, rhs: TuistConfig) -> Bool {
        return lhs.generationOptions == rhs.generationOptions
    }
}

public struct TemplateString: Encodable, Decodable, Hashable {
    let rawString: String
    public init(_ rawString: String) {
        self.rawString = rawString
    }
}

extension TemplateString: ExpressibleByStringLiteral {
    public init(stringLiteral: String) {
        rawString = stringLiteral
    }
}

extension TemplateString: CustomStringConvertible {
    public var description: String {
        return rawString
    }
}

extension TemplateString: ExpressibleByStringInterpolation {
    public init(stringInterpolation: StringInterpolation) {
        rawString = stringInterpolation.string
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var string: String

        public init(literalCapacity _: Int, interpolationCount _: Int) {
            string = String()
        }

        public mutating func appendLiteral(_ literal: String) {
            string.append(literal)
        }

        public func appendInterpolation(_: String) {}
    }
}

extension TemplateString {
    public enum Token: String {
        case projectName = "${project_name}"
    }
}

extension TemplateString.StringInterpolation {
    public mutating func appendInterpolation(_ token: TemplateString.Token) {
        string.append(token.rawValue)
    }
}

extension TemplateString.Token: Equatable {
    enum CodingKeys: String, CodingKey {
        case projectName
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        let enumCase = try container.decode(String.self)
        switch enumCase {
        case CodingKeys.projectName.rawValue: self = .projectName
        default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown enum case '\(enumCase)'"))
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .projectName: try container.encode(CodingKeys.projectName.rawValue)
        }
    }
}

extension TuistConfig.GenerationOption {
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
            let associatedValue0 = try associatedValues.decode(TemplateString.self)
            self = .xcodeProjectName(associatedValue0)
            return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown enum case"))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .generateManifest:
            _ = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .generateManifest)
        case let .xcodeProjectName(associatedValue0):
            var associatedValues = container.nestedUnkeyedContainer(forKey: .xcodeProjectName)
            try associatedValues.encode(associatedValue0)
        }
    }
}

public func == (lhs: TemplateString.Token, rhs: TemplateString.Token) -> Bool {
    switch (lhs, rhs) {
    case (.projectName, .projectName):
        return true
    }
}

public func == (lhs: TuistConfig.GenerationOption, rhs: TuistConfig.GenerationOption) -> Bool {
    switch (lhs, rhs) {
    case (.generateManifest, .generateManifest):
        return true
    case let (.xcodeProjectName(lhs), .xcodeProjectName(rhs)):
        return lhs == rhs
    default: return false
    }
}
