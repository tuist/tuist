import Foundation
import XCTest

extension XCTestCase {
    func XCTAssertEqualDictionaries<T: Hashable>(_ first: [T: Any],
                                                 _ second: [T: Any],
                                                 file: StaticString = #file,
                                                 line: UInt = #line) {
        let firstDictionary = NSDictionary(dictionary: first)
        let secondDictioanry = NSDictionary(dictionary: second)
        XCTAssertEqual(firstDictionary, secondDictioanry, file: file, line: line)
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
}
