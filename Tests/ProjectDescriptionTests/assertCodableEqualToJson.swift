import Foundation
import XCTest

func assertCodableEqualToJson<C: Codable>(_ subject: C, _ json: String, file: StaticString = #file, line: UInt = #line) {
    let decoder = JSONDecoder()
    let decoded = try! decoder.decode(C.self, from: json.data(using: .utf8)!)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let jsonData = try! encoder.encode(decoded)
    let subjectData = try! encoder.encode(subject)

    XCTAssert(jsonData == subjectData, "JSON does not match the encoded \(String(describing: subject))", file: file, line: line)
}
