/// Parsed attribute from user input
public struct ParsedAttribute: Encodable, Equatable {
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    /// Name (identifier) of attribute
    public let name: String
    /// Value of attribute
    public let value: String
}
