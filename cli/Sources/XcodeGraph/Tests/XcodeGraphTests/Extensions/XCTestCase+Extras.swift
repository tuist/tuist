import XCTest

extension XCTestCase {
    func XCTAssertCodable<C: Codable & Equatable>(_ subject: C, file _: StaticString = #file, line _: UInt = #line) {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        encoder.outputFormatting = .prettyPrinted

        let data = XCTTry(try encoder.encode(subject))
        let decoded = XCTTry(try decoder.decode(C.self, from: data))

        XCTAssertEqual(subject, decoded, "The subject is not equal to it's encoded & decoded version")
    }

    func XCTTry<T>(_ closure: @autoclosure @escaping () throws -> T, file: StaticString = #filePath, line: UInt = #line) -> T {
        var value: T!
        do {
            value = try closure()
        } catch {
            XCTFail("The code threw the following error: \(error)", file: file, line: line)
        }
        return value
    }

    func XCTAssertEqualDictionaries<T: Hashable>(
        _ first: [T: Any],
        _ second: [T: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let firstDictionary = NSDictionary(dictionary: first)
        let secondDictioanry = NSDictionary(dictionary: second)
        XCTAssertEqual(firstDictionary, secondDictioanry, file: file, line: line)
    }
}
