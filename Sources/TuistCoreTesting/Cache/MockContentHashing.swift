import Foundation
import TSCBasic
import TuistCore

public class MockContentHashing: ContentHashing {
    public init() {}

    public var hashDataSpy: Data?
    public var hashDataCallCount = 0
    public func hash(_ data: Data) throws -> String {
        hashDataSpy = data
        hashDataCallCount += 1
        return "\(String(describing: hashDataSpy?.base64EncodedString()))-hash"
    }

    public var hashStringSpy: String?
    public var hashStringCallCount = 0
    public func hash(_ string: String) throws -> String {
        hashStringSpy = string
        hashStringCallCount += 1
        return "\(string)-hash"
    }

    public var hashStringsSpy: [String]?
    public var hashStringsCallCount = 0
    public func hash(_ strings: [String]) throws -> String {
        hashStringsSpy = strings
        hashStringsCallCount += 1
        return strings.joined(separator: ";")
    }

    public var stubHashForPath: [AbsolutePath: String] = [:]
    public var hashPathCallCount = 0
    public func hash(path filePath: AbsolutePath) throws -> String {
        hashPathCallCount += 1
        return stubHashForPath[filePath] ?? ""
    }

    public var hashDictionarySpy: [String: String]?
    public var hashDictionaryCallCount = 0
    public func hash(_ dictionary: [String: String]) throws -> String {
        hashDictionaryCallCount += 1
        hashDictionarySpy = dictionary
        return dictionary.map { "\($0):\($1)" }.joined(separator: "-")
    }
}
