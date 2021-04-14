import Foundation

/// Enum representing customizable file header template for Xcode built-in file templates
///
/// Lets you define custom file header template for built-in Xcode templates, e.g. when you create new Swift file you can automatically have your custom define file header.
///
/// Tuist automatically performs several template transformations for you
///  - if your template starts with comment slashes (`//`) we remove them as they are added automatically by Xcode
///  - if your template doesn't start with comment and whitespace or newline, we add a space - otherwise your header would be glued to implicit comment slashes which you probably do not want
///  - if your template has trailing newline, we remove it as it is implicitly added by Xcode
public enum FileHeaderTemplate: Codable, Equatable, ExpressibleByStringInterpolation {
    enum CodingKeys: String, CodingKey {
        case file
        case string
    }

    /// Load template stored in file
    case file(Path)
    /// Use inline string as template
    case string(String)

    /// Creates file template as `.string(value)`
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
