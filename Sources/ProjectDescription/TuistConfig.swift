import Foundation

/// This model allows to configure Tuist.
public class TuistConfig: Encodable, Decodable, Equatable {
    /// Contains options related to the project generation.
    ///
    /// - generateManifestElement: When passed, Tuist generates the projects, targets and schemes to compile the project manifest.
    /// - xcodeProjectName(TemplateString): When passed, Tuist generates the project with the specific name on disk instead of using the project name.
    public enum GenerationOption: Encodable, Decodable, Equatable {
        case generateManifest
        case xcodeProjectName(TemplateString)
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

public struct TemplateString: Encodable, Decodable, Equatable {
    /// Contains a string that can be interpolated with options.
    let rawString: String
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

        public mutating func appendInterpolation(_ token: TemplateString.Token) {
            string.append(token.rawValue)
        }
    }
}

extension TemplateString {
    /// Provides a template for existing project properties.
    ///
    /// - projectName: The name of the project.
    public enum Token: String {
        case projectName = "${project_name}"
    }
}

extension TemplateString.Token: Equatable {
    public enum CodingKeys: String, CodingKey {
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

public func == (lhs: TuistConfig, rhs: TuistConfig) -> Bool {
    guard lhs.generationOptions == rhs.generationOptions else { return false }
    return true
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
        return lhs.rawString == rhs.rawString
    default: return false
    }
}
