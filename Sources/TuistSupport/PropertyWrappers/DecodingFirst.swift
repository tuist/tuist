/// Decodes the first value from array
/// - Throws: If array invalid or contains no values
@propertyWrapper
public struct DecodingFirst<Value>: Codable where Value: Codable {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        guard let value = try [Value](from: decoder).first else {
            throw "Expected an array with at least one value"
        }
        wrappedValue = value
    }

    public func encode(to encoder: Encoder) throws {
        try [wrappedValue].encode(to: encoder)
    }
}

extension DecodingFirst: Equatable where Value: Equatable {}
