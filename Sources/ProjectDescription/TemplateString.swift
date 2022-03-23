import Foundation

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
        rawString
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
    public enum Token: String, Equatable {
        case projectName = "${project_name}"
    }
}
