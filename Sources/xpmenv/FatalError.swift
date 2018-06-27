import Foundation

protocol FatalError: Error {
    var errorDescription: String { get }
}
