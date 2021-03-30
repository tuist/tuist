import Foundation

public protocol Formatting {
    func buildArguments() throws -> [String]
}
