import Foundation
import Testing

struct AtlasNativeFormTests {
    private func field(_ name: String, _ kind: String, required: Bool = false) -> AtlasNativeField {
        AtlasNativeField(value: ["path": [name], "kind": kind, "title": name, "required": required])
    }

    @Test func preservesFalseZeroAndMissingValues() throws {
        let flag = field("flag", "boolean")
        let count = field("count", "integer")
        let note = field("note", "string")
        let result = try AtlasNativeForm.input(fields: [flag, count, note], values: [flag.id: "false", count.id: "0"])
        #expect(result["flag"] as? Bool == false)
        #expect((result["count"] as? NSNumber)?.intValue == 0)
        #expect(result["note"] == nil)
    }

    @Test func createsNestedObjectsWithoutSplittingLiteralPropertyNames() throws {
        let nested = AtlasNativeField(value: ["path": ["address", "city"], "kind": "string", "required": true])
        let literal = field("address.city", "string")
        let result = try AtlasNativeForm.input(fields: [nested, literal], values: [nested.id: "Berlin", literal.id: "Literal"])
        #expect((result["address"] as? [String: String])?["city"] == "Berlin")
        #expect(result["address.city"] as? String == "Literal")
        #expect(nested.id != literal.id)
    }

    @Test func preservesRequiredObjectsWithOmittedOptionalChildren() throws {
        let child = AtlasNativeField(value: ["path": ["address", "city"], "kind": "string"])
        let result = try AtlasNativeForm.input(fields: [child], values: [:])
        #expect((result["address"] as? [String: String])?.isEmpty == true)
    }

    @Test func requiredMeansPresentNotNonempty() throws {
        let value = field("value", "string", required: true)
        let result = try AtlasNativeForm.input(fields: [value], values: [:])
        #expect(result["value"] as? String == "")
        #expect(throws: AtlasAuthenticationError.self) {
            try AtlasNativeForm.input(fields: [field("choice", "enum", required: true)], values: [:])
        }
    }

    @Test func booleanDefaultsUsePickerValues() {
        let value = AtlasNativeField(value: ["path": ["flag"], "kind": "boolean", "default": false])
        #expect(value.initial == "false")
    }

    @Test func rejectsNumericPrefixesInsteadOfSilentlyChangingInputs() throws {
        let amount = field("amount", "number")
        #expect(throws: AtlasAuthenticationError.self) {
            try AtlasNativeForm.input(fields: [amount], values: [amount.id: "12abc"])
        }
        let separator = Locale.current.decimalSeparator ?? "."
        let result = try AtlasNativeForm.input(fields: [amount], values: [amount.id: "-1\(separator)5"])
        #expect(result["amount"] as? NSDecimalNumber == NSDecimalNumber(string: "-1.5"))
    }
}
