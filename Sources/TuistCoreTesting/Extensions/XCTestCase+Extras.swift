import Basic
import Foundation
import XCTest

public extension XCTestCase {
    // MARK: - Fixtures

    func fixturePath(path: RelativePath) -> AbsolutePath {
        return AbsolutePath(#file)
            .appending(RelativePath("../../../../Tests/Fixtures"))
            .appending(path)
    }

    // MARK: - XCTAssertions

    func XCTAssertEqualPairs<T: Equatable>(_ subjects: [(T, T, Bool)], file: StaticString = #file, line: UInt = #line) {
        subjects.forEach {
            if $0.2 {
                XCTAssertEqual($0.0, $0.1, "Expected \($0.0) to be equal to \($0.1) but they are not.", file: file, line: line)
            } else {
                XCTAssertNotEqual($0.0, $0.1, "Expected \($0.0) to not be equal to \($0.1) but they are.", file: file, line: line)
            }
        }
    }

    func XCTAssertEqualDictionaries<T: Hashable>(_ first: [T: Any],
                                                 _ second: [T: Any],
                                                 file: StaticString = #file,
                                                 line: UInt = #line) {
        let firstDictionary = NSDictionary(dictionary: first)
        let secondDictioanry = NSDictionary(dictionary: second)
        XCTAssertEqual(firstDictionary, secondDictioanry, file: file, line: line)
    }

    func XCTAssertStandardOutput(_ printer: MockPrinter, pattern: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(printer.standardOutputMatches(with: pattern), """
        The pattern:
        \(pattern)
        
        Does not match the standard output:
        \(printer.standardOutput)
        """, file: file, line: line)
    }

    func XCTAssertDictionary<T: Hashable>(_ first: [T: Any],
                                          containsAll second: [T: Any],
                                          file: StaticString = #file,
                                          line: UInt = #line) {
        let filteredFirst = first.filter { second.keys.contains($0.key) }
        let firstDictionary = NSDictionary(dictionary: filteredFirst)
        let secondDictioanry = NSDictionary(dictionary: second)
        XCTAssertEqual(firstDictionary, secondDictioanry, file: file, line: line)
    }

    func XCTTry<T>(_ closure: @autoclosure @escaping () throws -> T, file: StaticString = #file, line: UInt = #line) -> T {
        var value: T!
        do {
            value = try closure()
        } catch {
            XCTFail("The code threw the following error: \(error)", file: file, line: line)
        }
        return value
    }

    func XCTAssertCodableEqualToJson<C: Codable>(_ subject: C, _ json: String, file: StaticString = #file, line: UInt = #line) {
        let decoder = JSONDecoder()
        let decoded = XCTTry(try decoder.decode(C.self, from: json.data(using: .utf8)!), file: file, line: line)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let jsonData = XCTTry(try encoder.encode(decoded), file: file, line: line)
        let subjectData = XCTTry(try encoder.encode(subject), file: file, line: line)

        XCTAssert(jsonData == subjectData, "JSON does not match the encoded \(String(describing: subject))", file: file, line: line)
    }

    func XCTAssertCodable<C: Codable & Equatable>(_ subject: C, file _: StaticString = #file, line _: UInt = #line) {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        encoder.outputFormatting = .prettyPrinted

        let data = XCTTry(try encoder.encode(subject))
        let decoded = XCTTry(try decoder.decode(C.self, from: data))

        XCTAssertEqual(subject, decoded, "The subject is not equal to it's encoded & decoded version")
    }

    func XCTAssertEncodableEqualToJson<C: Encodable>(_ subject: C, _ json: String, file: StaticString = #file, line: UInt = #line) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        let subjectData = XCTTry(try encoder.encode(subject))
        let subjectObject = XCTTry(try JSONSerialization.jsonObject(with: subjectData, options: []))
        let jsonObject = XCTTry(try JSONSerialization.jsonObject(with: json.data(using: .utf8)!, options: []))

        let errorString = """
        The JSON-encoded object doesn't match the given JSON:
        Given
        =======
        \(String(data: subjectData, encoding: .utf8)!)

        Expected
        =======
        \(json)
        """

        if let subjectArray = subjectObject as? [Any], let jsonArray = jsonObject as? [Any] {
            let subjectNSArray = NSArray(array: subjectArray)
            let jsonNSArray = NSArray(array: jsonArray)

            XCTAssertTrue(subjectNSArray.isEqual(to: jsonNSArray), errorString, file: file, line: line)

        } else if let subjectDictionary = subjectObject as? [String: Any], let jsonDictionary = jsonObject as? [String: Any] {
            let subjectNSDictionary = NSDictionary(dictionary: subjectDictionary)
            let jsonNSDictionary = NSDictionary(dictionary: jsonDictionary)

            XCTAssertTrue(subjectNSDictionary.isEqual(to: jsonNSDictionary), errorString, file: file, line: line)
        } else {
            XCTFail("Failed comparing the subject to the given JSON. Has the JSON the right format?")
        }
    }

    func XCTEmpty<S>(_ array: [S], file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(array.isEmpty, "Expected array to be empty but it's not. It contains the following elements: \(array)", file: file, line: line)
    }
}
