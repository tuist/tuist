import Foundation

struct AtlasNativeItem: Identifiable {
    let value: [String: Any]
    var id: String { text("id") }
    func text(_ key: String) -> String { value[key] as? String ?? "" }
    var sequence: UInt64 { (value["sequence"] as? NSNumber)?.uint64Value ?? 0 }
}

struct AtlasNativeField: Identifiable {
    let value: [String: Any]
    var path: [String] { value["path"] as? [String] ?? [] }
    var id: String { path.map { "\($0.utf8.count):\($0)" }.joined() }
    var kind: String { value["kind"] as? String ?? "string" }
    var title: String { value["title"] as? String ?? path.last ?? "Input" }
    var required: Bool { value["required"] as? Bool ?? false }
    var options: [String] { value["options"] as? [String] ?? [] }
    var hint: String {
        var parts = [value["description"] as? String ?? ""]
        for (key, label) in [("minimum", "Minimum"), ("maximum", "Maximum"),
                             ("min_length", "Minimum characters"), ("max_length", "Maximum characters")] {
            if let number = value[key] as? NSNumber { parts.append("\(label): \(number.stringValue)") }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ". ")
    }
    var initial: String {
        if kind == "boolean", let value = value["default"] as? Bool { return value ? "true" : "false" }
        if let value = value["default"] as? String { return value }
        if let value = value["default"] as? NSNumber { return value.stringValue }
        if required && kind == "boolean" { return "false" }
        if required && kind == "date" { return Self.date.string(from: Date()) }
        return ""
    }
    static var date: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

enum AtlasNativeForm {
    static func input(fields: [AtlasNativeField], values: [String: String]) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for field in fields {
            ensureObjects(field.path.dropLast(), into: &result)
            let text = values[field.id] ?? field.initial
            if text.isEmpty && !field.required { continue }
            if text.isEmpty && !["string", "text"].contains(field.kind) { throw failure("Provide \(field.title).") }
            let value: Any
            switch field.kind {
            case "boolean": value = text == "true" || text == "1"
            case "integer":
                guard let number = Int64(text) else { throw failure("Provide a whole number for \(field.title).") }
                value = NSNumber(value: number)
            case "number":
                let normalized = text.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
                guard normalized.range(of: #"^-?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil else {
                    throw failure("Provide a number for \(field.title).")
                }
                let number = NSDecimalNumber(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
                guard number != .notANumber else { throw failure("Provide a number for \(field.title).") }
                value = number
            default: value = text
            }
            insert(value, path: field.path[...], into: &result)
        }
        return result
    }

    private static func ensureObjects(_ path: ArraySlice<String>, into object: inout [String: Any]) {
        guard let key = path.first else { return }
        var nested = object[key] as? [String: Any] ?? [:]
        ensureObjects(path.dropFirst(), into: &nested)
        object[key] = nested
    }

    private static func insert(_ value: Any, path: ArraySlice<String>, into object: inout [String: Any]) {
        guard let key = path.first else { return }
        if path.count == 1 { object[key] = value } else {
            var nested = object[key] as? [String: Any] ?? [:]
            insert(value, path: path.dropFirst(), into: &nested)
            object[key] = nested
        }
    }

    static func pretty(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "Unavailable" }
        return text
    }
    private static func failure(_ message: String) -> AtlasAuthenticationError {
        AtlasAuthenticationError(kind: "invalid_input", message: message)
    }
}
