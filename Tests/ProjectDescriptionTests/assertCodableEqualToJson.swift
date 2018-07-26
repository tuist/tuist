import Foundation
import XCTest

func assertCodableEqualToJson<C: Codable>(_ subject: C, _ json: String) {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let decoded = try! decoder.decode(C.self, from: json.data(using: .utf8)!)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let jsonData = try! encoder.encode(decoded)
    let subjectData = try! encoder.encode(subject)

    XCTAssert(jsonData == subjectData, "JSON does not match the encoded \(String(describing: subject))")
}
