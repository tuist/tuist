import Foundation
import TuistCache
import Basic

public class MockContentHashing: ContentHashing {
    public init() {}

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
    public var hashFileAtPathCallCount = 0
    public func hash(fileAtPath filePath: AbsolutePath) throws -> String {
        hashFileAtPathCallCount += 1
        return stubHashForPath[filePath] ?? ""
    }
}
