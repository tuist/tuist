import Foundation
import Testing

@testable import ProjectDescription

struct ProductTests {
    @Test func test_toJSON() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let subjects: [(subject: [Product], json: String)] = [
            ([.app], "[\"app\"]"),
            ([.staticLibrary], "[\"static_library\"]"),
            ([.dynamicLibrary], "[\"dynamic_library\"]"),
            ([.framework], "[\"framework\"]"),
            ([.unitTests], "[\"unit_tests\"]"),
            ([.uiTests], "[\"ui_tests\"]"),
            ([.appClip], "[\"appClip\"]"),
        ]

        for (subject, json) in subjects {
            let decoded = try decoder.decode([Product].self, from: json.data(using: .utf8)!)
            let jsonData = try encoder.encode(decoded)
            let subjectData = try encoder.encode(subject)
            #expect(jsonData == subjectData)
        }
    }
}
