import Foundation
import TuistCache
import Basic

public class MockContentHashing: ContentHashing {
    public init(){}

    public var hashStringStub = ""
    public func hash(_ string: String) throws -> String {
        return hashStringStub
    }

    public var hashStringsStub = ""
    public var hashStringsSpy: [String]? = nil
    public func hash(_ strings: [String]) throws -> String {
        hashStringsSpy = strings
        return hashStringsStub
    }

    public var stubHashForPath: [AbsolutePath: String] = [:]
    public func hash(_ filePath: AbsolutePath) throws -> String {
        return stubHashForPath[filePath] ?? ""
    }
}

