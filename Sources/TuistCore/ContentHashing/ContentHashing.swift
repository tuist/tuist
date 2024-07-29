import Foundation
import Mockable
import Path

@Mockable
public protocol ContentHashing: FileContentHashing {
    func hash(_ data: Data) throws -> String
    func hash(_ string: String) throws -> String
    func hash(_ strings: [String]) throws -> String
    func hash(_ dictionary: [String: String]) throws -> String
    func hash(path filePath: AbsolutePath) throws -> String
}
