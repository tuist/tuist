import Foundation
import TuistCore
import XCTest

@testable import TuistEnvKit

final class MockHTTPClient: HTTPClienting {
    fileprivate var stubs: [URL: Result<Data, Error>] = [:]

    func succeed(url: URL, response: Data) {
        stubs[url] = .success(response)
    }

    func fail(url: URL, error: Error) {
        stubs[url] = .failure(error)
    }

    func read(url: URL) throws -> Data {
        if let result = stubs[url] {
            switch result {
            case let .failure(error): throw error
            case let .success(data): return data
            }
        } else {
            XCTFail("Request to non-stubbed URL \(url)")
            return Data()
        }
    }
}
