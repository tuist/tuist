// MARK: - Plist

public enum Plist {
    /// It represents the values of the .plist or .entitlements file dictionary.
    /// It ensures that the values used to define the content of the dynamically generated .plist or .entitlements files are valid
    public indirect enum Value: Codable, Equatable, Sendable, ExpressibleByStringInterpolation,
        ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral,
        ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral
    {
        /// It represents a string value.
        case string(String)
        /// It represents an integer value.
        case integer(Int)
        /// It represents a floating value.
        case real(Double)
        /// It represents a boolean value.
        case boolean(Bool)
        /// It represents a dictionary value.
        case dictionary([String: Value])
        /// It represents an array value.
        case array([Value])

        public init(stringLiteral value: String) {
            self = .string(value)
        }

        public init(integerLiteral value: Int) {
            self = .integer(value)
        }

        public init(floatLiteral value: Double) {
            self = .real(value)
        }

        public init(booleanLiteral value: Bool) {
            self = .boolean(value)
        }

        public init(dictionaryLiteral elements: (String, Plist.Value)...) {
            self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
        }

        public init(arrayLiteral elements: Plist.Value...) {
            self = .array(elements)
        }
    }
}
