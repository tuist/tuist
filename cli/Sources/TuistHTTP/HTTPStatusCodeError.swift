import Foundation

/// An error raised from a server response whose HTTP status code is known.
public protocol HTTPStatusCodeError: Error {
    var httpStatusCode: Int { get }
}
