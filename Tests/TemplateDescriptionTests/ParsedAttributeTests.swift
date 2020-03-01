import TuistSupportTesting
import XCTest

@testable import TemplateDescription

class ParsedAttributeTests: XCTestCase {
    func test_parsed_attribute_codable() throws {
        // Given
        let parsedAttribute = ParsedAttribute(name: "name", value: "value name")
            

        // Then
        XCTAssertCodable(parsedAttribute)
    }
    
    func test_getAttributes_when_attribute_present() throws {
        // Given
        let parsedAttributes: [ParsedAttribute] = [
            ParsedAttribute(name: "a", value: "a value"),
            ParsedAttribute(name: "b", value: "b value")
        ]
        let encoder = JSONEncoder()
        let parsedAttributesString = String(data: try encoder.encode(parsedAttributes), encoding: .utf8)
        let arguments = ["tuist", "something", "--attributes", parsedAttributesString ?? ""]
        
        // Then
        XCTAssertEqual(try getAttribute(for: "a", arguments: arguments), "a value")
    }
    
    func test_getAttributes_when_attribute_present_and_short_option() throws {
        // Given
        let parsedAttributes: [ParsedAttribute] = [
            ParsedAttribute(name: "a", value: "a value"),
            ParsedAttribute(name: "b", value: "b value")
        ]
        let encoder = JSONEncoder()
        let parsedAttributesString = String(data: try encoder.encode(parsedAttributes), encoding: .utf8)
        let arguments = ["tuist", "something", "-a", parsedAttributesString ?? ""]
        
        // Then
        XCTAssertEqual(try getAttribute(for: "a", arguments: arguments), "a value")
    }
    
    func test_getAttributes_error_when_attribute_not_present() throws {
        // Given
        let parsedAttributes: [ParsedAttribute] = [
            ParsedAttribute(name: "b", value: "b value")
        ]
        let encoder = JSONEncoder()
        let parsedAttributesString = String(data: try encoder.encode(parsedAttributes), encoding: .utf8)
        let arguments = ["tuist", "something", "-a", parsedAttributesString ?? ""]
        
        // Then
        XCTAssertThrowsSpecific(try getAttribute(for: "a", arguments: arguments), ParsingError.attributeNotFound("a"))
    }
    
    func test_getAttributes_error_when_attributes_not_provided() throws {
        // Given
        let arguments = ["tuist", "something", "--not-attributes"]
        
        // Then
        XCTAssertThrowsSpecific(try getAttribute(for: "a", arguments: arguments), ParsingError.attributesNotProvided)
    }
}
