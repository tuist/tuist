import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistEnvKit

final class MockHTTPClient: HTTPClienting {
    fileprivate var readStubs: [URL: Result<Data, Error>] = [:]
    fileprivate var downloadStubs: [URL: Result<AbsolutePath, Error>] = [:]

    func succeedRead(url: URL, response: Data) {
        readStubs[url] = .success(response)
    }

    func failRead(url: URL, error: Error) {
        readStubs[url] = .failure(error)
    }

    func read(url: URL) throws -> Data {
        if let result = readStubs[url] {
            switch result {
            case let .failure(error): throw error
            case let .success(data): return data
            }
        } else {
            XCTFail("Read request to non-stubbed URL \(url)")
            return Data()
        }
    }

    func download(url: URL, to: AbsolutePath) throws {
        if let result = downloadStubs[url] {
            switch result {
            case let .failure(error): throw error
            case let .success(from):
                do {
                    try FileHandler.shared.copy(from: from, to: to)
                } catch {
                    XCTFail("Error copying stubbed download to \(to.pathString)")
                }
            }
        } else {
            XCTFail("Download request to non-stubbed URL \(url)")
        }
    }
}
