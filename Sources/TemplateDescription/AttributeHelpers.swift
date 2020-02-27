import Foundation

/// Error that occurs when parsing attributes from input
enum ParsingError: Error, CustomStringConvertible {
    /// Thrown when could not find attribute in input
    case attributeNotFound(String)
    /// Thrown when attributes not provided
    case attributesNotProvided
    
    var description: String {
        switch self {
        case let .attributeNotFound(name):
            return "Could not find attribute \(name)"
        case .attributesNotProvided:
            return "You must provide --attributes option"
        }
    }
}

/// Returns value for `ParsedAttribute` of `name` from user input
/// - Parameters:
///     - name: Name of `ParsedAttribute`
/// - Returns: Value of `ParsedAttribute`
public func getAttribute(for name: String) throws -> String {
    let jsonDecoder = JSONDecoder()
    guard
        let attributesIndex = CommandLine.arguments.firstIndex(of: "--attributes"),
        CommandLine.arguments.endIndex > attributesIndex + 1,
        let data = CommandLine.arguments[attributesIndex + 1].data(using: .utf8)
        else { throw ParsingError.attributesNotProvided }
    
    let parsedAttributes = try jsonDecoder.decode([ParsedAttribute].self, from: data)
    guard let value = parsedAttributes.first(where: { $0.name == name })?.value else { throw ParsingError.attributeNotFound(name) }
    return value
}

/// Content to generate in `.generated` `Template.File`
public struct Content {
    /// - Parameters:
    ///     - generateContent: Closure to generate content with (can throw errors that will be displayed to the user if occurs)
    public init(_ generateContent: () throws -> String) {
        do {
            dumpIfNeeded(try generateContent())
        } catch let error {
            if let localizedDescriptionData = "\(error)".data(using: .utf8) {
                FileHandle.standardError.write(localizedDescriptionData)
            }
            exit(1)
        }
    }
}

/// Parsed attribute from user input
public struct ParsedAttribute: Codable {
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
    
    /// Name (identifier) of attribute
    public let name: String
    /// Value of attribute
    public let value: String
}
