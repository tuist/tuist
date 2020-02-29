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
