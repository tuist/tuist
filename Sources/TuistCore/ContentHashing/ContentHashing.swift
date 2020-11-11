import Foundation

public protocol ContentHashing: FileContentHashing {
    func hash(_ data: Data) throws -> String
    func hash(_ string: String) throws -> String
    func hash(_ strings: [String]) throws -> String
    func hash(_ dictionary: [String: String]) throws -> String
}
