import Foundation

/*
 This source file is part of the Swift.org open source project
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/// A very minimal JSON type to serialize the manifest.
enum JSON {
    case null
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)
    case array([JSON])
    case dictionary([String: JSON])
}

protocol JSONConvertible {
    func toJSON() -> JSON
}

extension Array: JSONConvertible where Element: JSONConvertible {
    func toJSON() -> JSON {
        return .array(map({ $0.toJSON() }))
    }
}

extension Dictionary: JSONConvertible where Key == String, Value: JSONConvertible {
    func toJSON() -> JSON {
        return .dictionary(mapValues({ $0.toJSON() }))
    }
}

extension String: JSONConvertible {
    func toJSON() -> JSON {
        return .string(self)
    }
}

extension Bool: JSONConvertible {
    func toJSON() -> JSON {
        return .bool(self)
    }
}

extension JSON {
    /// Converts the JSON to string representation.
    // FIXME: No escaping implemented for now.
    func toString() -> String {
        switch self {
        case .null:
            return "null"
        case let .bool(value):
            return value ? "true" : "false"
        case let .int(value):
            return value.description
        case let .double(value):
            return value.debugDescription
        case let .string(value):
            return "\"" + value + "\""
        case let .array(contents):
            return "[" + contents.map({ $0.toString() }).joined(separator: ", ") + "]"
        case let .dictionary(contents):
            var output = "{"
            for (i, key) in contents.keys.sorted().enumerated() {
                if i != 0 { output += ", " }
                output += "\"" + key + "\"" + ": " + contents[key]!.toString()
            }
            output += "}"
            return output
        }
    }
}
