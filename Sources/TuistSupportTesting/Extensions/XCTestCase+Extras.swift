import Foundation
import Path
import TuistSupport
import XCTest

extension XCTestCase {
    // MARK: - Fixtures

    public func fixturePath(path: RelativePath) -> AbsolutePath {
        try! AbsolutePath(validating: #file) // swiftlint:disable:this force_try
            .appending(try! RelativePath(validating: "../../../../Tests/Fixtures")) // swiftlint:disable:this force_try
            .appending(path)
    }

    // MARK: - XCTAssertions

    public func XCTAssertEmpty(_ collection: some Collection, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(
            collection.count,
            0,
            "Expected to be empty but it has \(collection.count) elements",
            file: file,
            line: line
        )
    }

    public func XCTAssertNotEmpty(_ collection: some Collection, file: StaticString = #file, line: UInt = #line) {
        XCTAssertNotEqual(collection.count, 0, "Expected to not be empty but it has 0 elements", file: file, line: line)
    }

    // swiftlint:disable:next large_tuple
    public func XCTAssertEqualPairs<T: Equatable>(_ subjects: [(T, T, Bool)], file: StaticString = #file, line: UInt = #line) {
        for subject in subjects {
            if subject.2 {
                XCTAssertEqual(
                    subject.0,
                    subject.1,
                    "Expected \(subject.0) to be equal to \(subject.1) but they are not.",
                    file: file,
                    line: line
                )
            } else {
                XCTAssertNotEqual(
                    subject.0,
                    subject.1,
                    "Expected \(subject.0) to not be equal to \(subject.1) but they are.",
                    file: file,
                    line: line
                )
            }
        }
    }

    public func XCTAssertEqualDictionaries<T: Hashable>(
        _ first: [T: Any],
        _ second: [T: Any],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let firstDictionary = NSDictionary(dictionary: first)
        let secondDictioanry = NSDictionary(dictionary: second)
        XCTAssertEqual(firstDictionary, secondDictioanry, file: file, line: line)
    }

    public func XCTAssertStandardOutput(pattern: String, file: StaticString = #file, line: UInt = #line) {
        let standardOutput = TestingLogHandler.collected[.info, <=]

        let message = """
        The standard output:
        ===========
        \(standardOutput)

        Doesn't contain the expected output:
        ===========
        \(pattern)
        """

        XCTAssertTrue(standardOutput.contains(pattern), message, file: file, line: line)
    }

    public func XCTAssertStandardError(pattern: String, file: StaticString = #file, line: UInt = #line) {
        let standardError = TestingLogHandler.collected[.error, ==]

        let message = """
        The standard error:
        ===========
        \(standardError)

        Doesn't contain the expected output:
        ===========
        \(pattern)
        """

        XCTAssertTrue(standardError.contains(pattern), message, file: file, line: line)
    }

    public func XCTTry<T>(_ closure: @autoclosure @escaping () throws -> T, file: StaticString = #file, line: UInt = #line) -> T {
        var value: T!
        do {
            value = try closure()
        } catch {
            XCTFail("The code threw the following error: \(error)", file: file, line: line)
        }
        return value
    }

    public func XCTAssertThrowsSpecific<Error: Swift.Error & Equatable>(
        _ closure: @autoclosure () throws -> some Any,
        _ error: Error,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            _ = try closure()
        } catch let closureError as Error {
            XCTAssertEqual(error, closureError, file: file, line: line)
            return
        } catch let closureError {
            XCTFail("\(error) is not equal to: \(closureError)", file: file, line: line)
            return
        }
        XCTFail("No error was thrown", file: file, line: line)
    }

    public func XCTAssertThrowsSpecific<Error: Swift.Error & Equatable>(
        _ closure: () async throws -> some Any,
        _ error: Error,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        do {
            _ = try await closure()
        } catch let closureError as Error {
            XCTAssertEqual(closureError, error, file: file, line: line)
            return
        } catch let closureError {
            XCTFail("\(error) is not equal to: \(closureError)", file: file, line: line)
            return
        }
        XCTFail("No error was thrown", file: file, line: line)
    }

    public func XCTAssertThrowsSpecific<Error: Swift.Error & Equatable>(
        _ closure: @autoclosure () async throws -> some Any,
        _ error: Error,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        do {
            _ = try await closure()
        } catch let closureError as Error {
            XCTAssertEqual(closureError, error, file: file, line: line)
            return
        } catch let closureError {
            XCTFail("\(error) is not equal to: \(closureError)", file: file, line: line)
            return
        }
        XCTFail("No error was thrown", file: file, line: line)
    }

    public func XCTAssertThrows(
        _ closure: @autoclosure () async throws -> some Any,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        do {
            _ = try await closure()
            XCTFail("No error was thrown", file: file, line: line)
        } catch {
            // Succeeded
        }
    }

    public func XCTAssertCodableEqualToJson<C: Codable>(
        _ subject: C,
        _ json: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let decoder = JSONDecoder()
        let decoded = XCTTry(try decoder.decode(C.self, from: json.data(using: .utf8)!), file: file, line: line)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let jsonData = XCTTry(try encoder.encode(decoded), file: file, line: line)
        let subjectData = XCTTry(try encoder.encode(subject), file: file, line: line)

        XCTAssert(
            jsonData == subjectData,
            "JSON does not match the encoded \(String(describing: subject))",
            file: file,
            line: line
        )
    }

    public func XCTAssertCodable<C: Codable & Equatable>(_ subject: C, file _: StaticString = #file, line _: UInt = #line) {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        encoder.outputFormatting = .prettyPrinted

        let data = XCTTry(try encoder.encode(subject))
        let decoded = XCTTry(try decoder.decode(C.self, from: data))

        XCTAssertEqual(subject, decoded, "The subject is not equal to it's encoded & decoded version")
    }

    public func XCTAssertEncodableEqualToJson(
        _ subject: some Encodable,
        _ json: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
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

    /// Asserts that a `json` object decoded as a `T` type is equal to an `expected` value.
    public func XCTAssertDecodableEqualToJson<C: Decodable & Equatable>(
        _ json: String,
        _ expected: C,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let jsonData = json.data(using: .utf8) else {
            XCTFail("Invalid JSON.", file: file, line: line)
            return
        }

        let decoder = JSONDecoder()
        let decoded = XCTTry(try decoder.decode(C.self, from: jsonData), file: file, line: line)

        let errorString = """
        The JSON-decoded object doesn't match the expected value:
        Given
        =======
        \(decoded)

        Expected
        =======
        \(expected)
        """

        XCTAssertEqual(decoded, expected, errorString, file: file, line: line)
    }

    public func XCTEmpty(_ array: [some Any], file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(
            array.isEmpty,
            "Expected array to be empty but it's not. It contains the following elements: \(array)",
            file: file,
            line: line
        )
    }

    // `XCTUnwrap` is unavailable when building using SwiftPM
    //
    // - related: https://bugs.swift.org/browse/SR-11501

    public enum XCTUnwrapError: Error {
        case nilValueDetected
    }

    public func XCTUnwrap<T>(_ element: T?, file: StaticString = #file, line: UInt = #line) throws -> T {
        guard let element else {
            XCTFail(
                "expected non-nil value of type \"\(type(of: T.self))\"",
                file: file,
                line: line
            )
            throw XCTUnwrapError.nilValueDetected
        }
        return element
    }

    @discardableResult public func XCTAssertContainsElementOfType<T>(
        _ collection: [Any],
        _ type: T.Type,
        file: StaticString = #file,
        line: UInt = #line
    ) -> T? {
        guard let element = collection.first(where: { $0 is T }) else {
            XCTFail("Didn't find an element of type \(String(describing: type))", file: file, line: line)
            return nil
        }
        return element as? T
    }

    public func XCTAssertDoesntContainElementOfType<T>(
        _ collection: [Any],
        _ type: T.Type,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if let element = collection.first(where: { $0 is T }) {
            XCTFail("Found an element of type \(String(describing: type)): \(element)", file: file, line: line)
        }
    }

    @discardableResult public func XCTAssertContainsElementOfType<T, U>(
        _ collection: [Any],
        _ type: T.Type,
        after: U.Type,
        file: StaticString = #file,
        line: UInt = #line
    ) -> T? {
        guard let elementIndex = collection.lastIndex(where: { $0 is T }) else {
            XCTFail("Didn't found an element of type \(String(describing: type))", file: file, line: line)
            return nil
        }
        guard let previousElementIndex = collection.firstIndex(where: { $0 is U }) else {
            XCTFail("Didn't found an element of type \(String(describing: after))", file: file, line: line)
            return nil
        }
        XCTAssertTrue(
            elementIndex > previousElementIndex,
            "Expected element of type \(String(describing: type)) to be after an element of type \(String(describing: after)) but it's not",
            file: file,
            line: line
        )
        return collection[elementIndex] as? T
    }

    @discardableResult public func XCTAssertContainsElementOfType<T, U>(
        _ collection: [Any],
        _ type: T.Type,
        before: U.Type,
        file: StaticString = #file,
        line: UInt = #line
    ) -> T? {
        guard let elementIndex = collection.firstIndex(where: { $0 is T }) else {
            XCTFail("Didn't found an element of type \(String(describing: type))", file: file, line: line)
            return nil
        }
        guard let afterElementIndex = collection.lastIndex(where: { $0 is U }) else {
            XCTFail("Didn't found an element of type \(String(describing: before))", file: file, line: line)
            return nil
        }
        XCTAssertTrue(
            elementIndex < afterElementIndex,
            "Expected element of type \(String(describing: type)) to be before an element of type \(String(describing: before)) but it's not",
            file: file,
            line: line
        )
        return collection[elementIndex] as? T
    }

    /// Asserts that a directory at given path contains expected elements.
    /// It does not check the contents of a directory recursively.
    /// - Throws: An error if the directory at given path does not exist.
    public func XCTAssertDirectoryContentEqual(
        _ directory: AbsolutePath,
        _ expected: [String],
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let directoryContent = try FileHandler.shared
            .contentsOfDirectory(directory)
            .map(\.pathString)
            .sorted()

        let expectedContent = try expected
            .map { directory.appending(try RelativePath(validating: $0)) }
            .map(\.pathString)
            .sorted()

        let message = """
        The directory content:
        ===========
        \(directoryContent.isEmpty ? "<Empty>" : directoryContent.joined(separator: "\n"))

        Doesn't equal to expected:
        ===========
        \(expectedContent.isEmpty ? "<Empty>" : expectedContent.joined(separator: "\n"))
        """

        XCTAssertEqual(directoryContent, expectedContent, message, file: file, line: line)
    }
}
